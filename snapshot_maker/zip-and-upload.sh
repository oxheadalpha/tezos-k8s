#!/bin/bash

BLOCK_HEIGHT=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)
BLOCK_HASH=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH)
BLOCK_TIMESTAMP=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)
TEZOS_VERSION=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/TEZOS_VERSION)
NETWORK="${NAMESPACE%%-*}"

S3_BUCKET="${NETWORK}.xtz-shots.io"

cd /

# If block_height is not set than init container failed, exit this container
[ -z "${BLOCK_HEIGHT}" ] && exit 1

printf "%s BLOCK_HASH is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH))\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
printf "%s BLOCK_HEIGHT is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
printf "%s BLOCK_TIMESTAMP is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# Download base.json or create if if it doesn't exist
if ! aws s3api head-object --bucket "${S3_BUCKET}" --key "base.json" > /dev/null; then
    printf "%s Check base.json : Did not detect in S3.  Creating base.json locally to append and upload later.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if ! touch base.json; then
        printf "%s Create base.json : Error creating file base.json locally. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Create base.json : Created file base.json. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
else
    printf "%s Check base.json : Exists in S3.  Downloading to append new information and will upload later. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if ! aws s3 cp s3://"${S3_BUCKET}"/base.json base.json > /dev/null; then
        printf "%s Download base.json : Error downloading file base.json from S3. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Download base.json : Downloaded file base.json from S3. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
fi

# Check if base.json exists locally
if test -f base.json; then
    printf "%s Check base.json : File base.json exists locally. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    # Write empty array if empty
    if ! [ -s "base.json" ]
    then
    # It is. Write an empty array to it
    echo '[]' > "base.json"
    fi
else
    printf "%s Check base.json : File base.json does not exist locally. \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

#
# Archive Tarball
#

# Do not take archive tarball in rolling namespace
if [ "${HISTORY_MODE}" = archive ]; then
    printf "%s ********************* Archive Tarball *********************\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    ARCHIVE_TARBALL_FILENAME=tezos-"${NETWORK}"-archive-tarball-"${BLOCK_HEIGHT}".lz4
    printf "%s Archive tarball filename is ${ARCHIVE_TARBALL_FILENAME}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    # LZ4 /var/tezos/node selectively and upload to S3
    printf "%s Archive Tarball : Tarballing /var/tezos/node, LZ4ing, and uploading to S3...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > archive-tarball.sha256) \
    | aws s3 cp - s3://"${S3_BUCKET}"/"${ARCHIVE_TARBALL_FILENAME}" --expected-size 322122547200

    SHA256=$(cat archive-tarball.sha256)

    FILESIZE_BYTES=$(aws s3api head-object \
        --bucket "${S3_BUCKET}" \
        --key "${ARCHIVE_TARBALL_FILENAME}" \
        --query ContentLength \
        --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

    # Add file to base.json
    # have to do it here because base.json is being overwritten
    # by other snapshot actions that are faster
    tmp=$(mktemp)
    cp base.json "${tmp}"

    if ! jq \
    --arg BLOCK_HASH "$BLOCK_HASH" \
    --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
    --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
    --arg ARCHIVE_TARBALL_FILENAME "$ARCHIVE_TARBALL_FILENAME" \
    --arg SHA256 "$SHA256" \
    --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
    --arg FILESIZE "$FILESIZE" \
    --arg TEZOS_VERSION "$TEZOS_VERSION" \
    --arg NETWORK "$NETWORK" \
    --arg HISTORY_MODE "archive" \
    --arg ARTIFACT_TYPE "tarball" \
    '. |= 
    [
        {
                ($ARCHIVE_TARBALL_FILENAME): {
                "contents": {
                    "block_hash": $BLOCK_HASH,
                    "block_height": $BLOCK_HEIGHT,
                    "block_timestamp": $BLOCK_TIMESTAMP,
                    "sha256": $SHA256,
                    "filesize_bytes": $FILESIZE_BYTES,
                    "filesize": $FILESIZE,
                    "tezos_version": $TEZOS_VERSION,
                    "chain_name": $NETWORK,
                    "history_mode": $HISTORY_MODE,
                    "artifact_type": $ARTIFACT_TYPE
                }
            }
        }
    ] 
    + .' "${tmp}" > base.json && rm "${tmp}";then
        printf "%s Archive Tarball base.json: Error updating base.json.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Archive Tarball : Sucessfully updated base.json with artifact information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi

    #Upload base.json
    if ! aws s3 cp base.json s3://"${S3_BUCKET}"/base.json; then
        printf "%s Upload base.json : Error uploading file base.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Upload base.json : File base.json sucessfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi

    # Check if archive-tarball exists in S3 and process redirect
    if ! aws s3api head-object --bucket "${S3_BUCKET}" --key "${ARCHIVE_TARBALL_FILENAME}" > /dev/null; then
        printf "%s Archive Tarball : Error uploading ${ARCHIVE_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Archive Tarball : Upload of ${ARCHIVE_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET} successful!\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

        # Create archive tarball metadata json
        jq -n \
        --arg BLOCK_HASH "${BLOCK_HASH}" \
        --arg BLOCK_HEIGHT "${BLOCK_HEIGHT}" \
        --arg BLOCK_TIMESTAMP "${BLOCK_TIMESTAMP}" \
        --arg ARCHIVE_TARBALL_FILENAME "${ARCHIVE_TARBALL_FILENAME}" \
        --arg SHA256 "${SHA256}" \
        --arg FILESIZE_BYTES "${FILESIZE_BYTES}" \
        --arg FILESIZE "${FILESIZE}" \
        --arg TEZOS_VERSION "${TEZOS_VERSION}" \
        --arg NETWORK "${NETWORK}" \
        --arg HISTORY_MODE "archive" \
        --arg ARTIFACT_TYPE "tarball" \
        '{
            "block_hash": $BLOCK_HASH, 
            "block_height": $BLOCK_HEIGHT, 
            "block_timestamp": $BLOCK_TIMESTAMP,
            "archive_tarball_filename": $ARCHIVE_TARBALL_FILENAME,
            "sha256": $SHA256,
            "filesize_bytes": $FILESIZE_BYTES,
            "filesize": $FILESIZE, 
            "tezos_version": $TEZOS_VERSION,
            "chain_name": $NETWORK,
            "history_mode": $HISTORY_MODE,
            "artifact_type": $ARTIFACT_TYPE
        }' \
        > "${ARCHIVE_TARBALL_FILENAME}".json

        # Check metadata json exists
        if [ -f "${ARCHIVE_TARBALL_FILENAME}".json ]; then
            printf "%s Archive Tarball : ${ARCHIVE_TARBALL_FILENAME}.json created.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : Error creating ${ARCHIVE_TARBALL_FILENAME}.json.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload archive tarball metadata json
        if ! aws s3 cp "${ARCHIVE_TARBALL_FILENAME}".json s3://"${S3_BUCKET}"/"${ARCHIVE_TARBALL_FILENAME}".json; then
            printf "%s Archive Tarball : Error uploading ${ARCHIVE_TARBALL_FILENAME}.json to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : Artifact JSON ${ARCHIVE_TARBALL_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Create archive tarball redirect file
        if ! touch archive-tarball; then
            printf "%s Archive Tarball : Error creating ${NETWORK}-archive-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : ${NETWORK}-archive-tarball created sucessfully.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload redirect file and set header for previously uploaded LZ4 File
        if ! aws s3 cp archive-tarball s3://"${S3_BUCKET}" --website-redirect /"${ARCHIVE_TARBALL_FILENAME}" --cache-control 'no-cache'; then
            printf "%s Archive Tarball : Error uploading ${NETWORK}-archive-tarball. to S3\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : Upload of ${NETWORK}-archive-tarball sucessful to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Archive Tarball json redirect file
        if ! touch archive-tarball-metadata; then
            printf "%s Archive Tarball : Error creating ${NETWORK}-archive-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : Created ${NETWORK}-archive-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload archive tarball json redirect file and set header for previously uploaded archive tarball json File
        if ! aws s3 cp archive-tarball-metadata s3://"${S3_BUCKET}" --website-redirect /"${ARCHIVE_TARBALL_FILENAME}".json --cache-control 'no-cache'; then
            printf "%s archive Tarball : Error uploading ${NETWORK}-archive-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s archive Tarball : Uploaded ${NETWORK}-archive-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi
    fi
else
    printf "%s Archive Tarball : Not creating archive tarball since this is a rolling job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

# Rolling artifacts for rolling history mode
if [ "${HISTORY_MODE}" = rolling ]; then
    #
    # Rolling snapshot and tarball vars
    #
    ROLLING_SNAPSHOT_FILENAME="${NETWORK}"-"${BLOCK_HEIGHT}".rolling
    ROLLING_SNAPSHOT=/"${HISTORY_MODE}"-snapshot-cache-volume/"${ROLLING_SNAPSHOT_FILENAME}"
    ROLLING_TARBALL_FILENAME=tezos-"${NETWORK}"-rolling-tarball-"${BLOCK_HEIGHT}".lz4
    IMPORT_IN_PROGRESS=/rolling-tarball-restore/snapshot-import-in-progress

    # Wait for rolling snapshot file
    while  ! [ -f "${ROLLING_SNAPSHOT}" ]; do
        printf "%s Waiting for ${ROLLING_SNAPSHOT} to exist...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        
        if [ "${HISTORY_MODE}" = archive ]; then
            sleep 15m
        else
            sleep 2m
        fi
    done

    # Wait for rolling snapshot to import to temporary filesystem for tarball.
    while  [ -f "${IMPORT_IN_PROGRESS}" ]; do
        printf "%s Waiting for snapshot to import...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if [ "${HISTORY_MODE}" = archive ]; then
            sleep 15m
        else
            sleep 2m
        fi
    done

    # LZ4 /"${HISTORY_MODE}"-snapshot-cache-volume/var/tezos/node selectively and upload to S3
    printf "%s ********************* Rolling Tarball *********************\\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    printf "%s Rolling Tarball : Tarballing /rolling-tarball-restore/var/tezos/node, LZ4ing, and uploading to S3...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /rolling-tarball-restore/var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > rolling-tarball.sha256) \
    | aws s3 cp - s3://"${S3_BUCKET}"/"${ROLLING_TARBALL_FILENAME}" --expected-size 322122547200

    SHA256=$(cat rolling-tarball.sha256)

    FILESIZE_BYTES=$(aws s3api head-object \
    --bucket "${S3_BUCKET}" \
    --key "${ROLLING_TARBALL_FILENAME}" \
    --query ContentLength \
    --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

    # Add file to base.json
    tmp=$(mktemp)
    cp base.json "${tmp}"

    if ! jq \
    --arg BLOCK_HASH "$BLOCK_HASH" \
    --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
    --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
    --arg ROLLING_TARBALL_FILENAME "$ROLLING_TARBALL_FILENAME" \
    --arg SHA256 "$SHA256" \
    --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
    --arg FILESIZE "$FILESIZE" \
    --arg TEZOS_VERSION "$TEZOS_VERSION" \
    --arg NETWORK "$NETWORK" \
    --arg HISTORY_MODE "rolling" \
    --arg ARTIFACT_TYPE "tarball" \
    '. |= 
    [
        {
                ($ROLLING_TARBALL_FILENAME): {
                "contents": {
                    "block_hash": $BLOCK_HASH,
                    "block_height": $BLOCK_HEIGHT,
                    "block_timestamp": $BLOCK_TIMESTAMP,
                    "sha256": $SHA256,
                    "filesize_bytes": $FILESIZE_BYTES,
                    "filesize": $FILESIZE,
                    "tezos_version": $TEZOS_VERSION,
                    "chain_name": $NETWORK,
                    "history_mode": $HISTORY_MODE,
                    "artifact_type": $ARTIFACT_TYPE
                }
            }
        }
    ] 
    + .' "${tmp}" > base.json && rm "${tmp}";then
        printf "%s Rolling Tarball base.json: Error updating base.json.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Rolling Tarball : Sucessfully updated base.json with artifact information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi

    #Upload base.json
    if ! aws s3 cp base.json s3://"${S3_BUCKET}"/base.json; then
        printf "%s Upload base.json : Error uploading file base.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Upload base.json : File base.json sucessfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi

    # Check if rolling-tarball exists and process redirect
    if ! aws s3api head-object --bucket "${S3_BUCKET}" --key "${ROLLING_TARBALL_FILENAME}" > /dev/null; then
        printf "%s Rolling Tarball : Error uploading ${ROLLING_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s Rolling Tarball : Upload of ${ROLLING_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET} successful!\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

        jq -n \
        --arg BLOCK_HASH "$BLOCK_HASH" \
        --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
        --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
        --arg ROLLING_TARBALL_FILENAME "$ROLLING_TARBALL_FILENAME" \
        --arg SHA256 "$SHA256" \
        --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
        --arg FILESIZE "$FILESIZE" \
        --arg TEZOS_VERSION "$TEZOS_VERSION" \
        --arg NETWORK "$NETWORK" \
        --arg HISTORY_MODE "rolling" \
        --arg ARTIFACT_TYPE "tarball" \
        '{
            "block_hash": $BLOCK_HASH, 
            "block_height": $BLOCK_HEIGHT, 
            "block_timestamp": $BLOCK_TIMESTAMP,
            "rolling_tarball_filename": $ROLLING_TARBALL_FILENAME,
            "sha256": $SHA256,
            "filesize_bytes": $FILESIZE_BYTES,
            "filesize": $FILESIZE, 
            "tezos_version": $TEZOS_VERSION,
            "chain_name": $NETWORK,
            "history_mode": $HISTORY_MODE,
            "artifact_type": $ARTIFACT_TYPE
        }' \
        > "${ROLLING_TARBALL_FILENAME}".json
        
        if [ -f "${ROLLING_TARBALL_FILENAME}".json ]; then
            printf "%s Rolling Tarball : ${ROLLING_TARBALL_FILENAME}.json created.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Error creating ${ROLLING_TARBALL_FILENAME}.json locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # upload metadata json
        if ! aws s3 cp "${ROLLING_TARBALL_FILENAME}".json s3://"${S3_BUCKET}"/"${ROLLING_TARBALL_FILENAME}".json; then
            printf "%s Rolling Tarball : Error uploading ${ROLLING_TARBALL_FILENAME}.json to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Metadata JSON ${ROLLING_TARBALL_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi
        
        # Tarball redirect file
        if ! touch rolling-tarball; then
            printf "%s Rolling Tarball : Error creating ${NETWORK}-rolling-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Created ${NETWORK}-rolling-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload redirect file and set header for previously uploaded LZ4 File
        if ! aws s3 cp rolling-tarball s3://"${S3_BUCKET}" --website-redirect /"${ROLLING_TARBALL_FILENAME}" --cache-control 'no-cache'; then
            printf "%s Rolling Tarball : Error uploading ${NETWORK}-rolling-tarball file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Uploaded ${NETWORK}-rolling-tarball file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Rolling Tarball json redirect file
        if ! touch rolling-tarball-metadata; then
            printf "%s Rolling Tarball : Error creating ${NETWORK}-rolling-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Created ${NETWORK}-rolling-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload rolling tarball json redirect file and set header for previously uploaded rolling tarball json File
        if ! aws s3 cp rolling-tarball-metadata s3://"${S3_BUCKET}" --website-redirect /"${ROLLING_TARBALL_FILENAME}".json --cache-control 'no-cache'; then
            printf "%s Rolling Tarball : Error uploading ${NETWORK}-rolling-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tarball : Uploaded ${NETWORK}-rolling-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi
    fi

    #
    # Rolling Snapshot
    #
    printf "%s ********************* Rolling Tezos Snapshot *********************\\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    # If rolling snapshot exists locally
    if test -f "${ROLLING_SNAPSHOT}"; then
        printf "%s ${ROLLING_SNAPSHOT} exists!\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        # Upload rolling snapshot to S3 and error on failure
        if ! aws s3 cp "${ROLLING_SNAPSHOT}" s3://"${S3_BUCKET}"; then
            printf "%s Rolling Tezos : Error uploading ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Rolling Tezos : Sucessfully uploaded ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            printf "%s Rolling Tezos : Uploading redirect...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

            FILESIZE_BYTES=$(stat -c %s "${ROLLING_SNAPSHOT}")
            printf "FILESIZE_BYTES COMMAND=%s\n" "$(stat -c %s "${ROLLING_SNAPSHOT}")"
            printf "FILESIZE_BYTES VARIABLE=%s\n" "${FILESIZE_BYTES}"

            FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs )
            SHA256=$(sha256sum "${ROLLING_SNAPSHOT}" | awk '{print $1}')

            # Add file to base.json
            tmp=$(mktemp)
            cp base.json "${tmp}"

            if ! jq \
            --arg BLOCK_HASH "$BLOCK_HASH" \
            --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
            --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
            --arg ROLLING_SNAPSHOT_FILENAME "$ROLLING_SNAPSHOT_FILENAME" \
            --arg SHA256 "$SHA256" \
            --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
            --arg FILESIZE "$FILESIZE" \
            --arg TEZOS_VERSION "$TEZOS_VERSION" \
            --arg NETWORK "$NETWORK" \
            --arg HISTORY_MODE "rolling" \
            --arg ARTIFACT_TYPE "tezos-snapshot" \
            '. |= 
            [
                {
                        ($ROLLING_SNAPSHOT_FILENAME): {
                        "contents": {
                            "block_hash": $BLOCK_HASH,
                            "block_height": $BLOCK_HEIGHT,
                            "block_timestamp": $BLOCK_TIMESTAMP,
                            "sha256": $SHA256,
                            "filesize_bytes": $FILESIZE_BYTES,
                            "filesize": $FILESIZE,
                            "tezos_version": $TEZOS_VERSION,
                            "chain_name": $NETWORK,
                            "history_mode": $HISTORY_MODE,
                            "artifact_type": $ARTIFACT_TYPE
                        }
                    }
                }
            ] 
            + .' "${tmp}" > base.json && rm "${tmp}";then
                printf "%s Rolling Snapshot base.json: Error updating base.json.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            else
                printf "%s Rolling Snapshot : Sucessfully updated base.json with artifact information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            fi

            #Upload base.json
            if ! aws s3 cp base.json s3://"${S3_BUCKET}"/base.json; then
                printf "%s Upload base.json : Error uploading file base.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            else
                printf "%s Upload base.json : File base.json sucessfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            fi

            jq -n \
            --arg BLOCK_HASH "$BLOCK_HASH" \
            --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
            --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
            --arg ROLLING_SNAPSHOT_FILENAME "$ROLLING_SNAPSHOT_FILENAME" \
            --arg SHA256 "$SHA256" \
            --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
            --arg FILESIZE "$FILESIZE" \
            --arg TEZOS_VERSION "$TEZOS_VERSION" \
            --arg NETWORK "$NETWORK" \
            --arg HISTORY_MODE "rolling" \
            --arg ARTIFACT_TYPE "tezos-snapshot" \
            '{
                "block_hash": $BLOCK_HASH, 
                "block_height": $BLOCK_HEIGHT, 
                "block_timestamp": $BLOCK_TIMESTAMP,
                "rolling_snapshot_filename": $ROLLING_SNAPSHOT_FILENAME,
                "filesize_bytes": $FILESIZE_BYTES,
                "filesize": $FILESIZE,
                "sha256": $SHA256,
                "tezos_version": $TEZOS_VERSION,
                "chain_name": $NETWORK,
                "history_mode": $HISTORY_MODE,
                "artifact_type": $ARTIFACT_TYPE
            }' \
            > "${ROLLING_SNAPSHOT_FILENAME}".json
            
            printf "%s Rolling Tezos : Metadata JSON created.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

            # upload metadata json
            aws s3 cp "${ROLLING_SNAPSHOT_FILENAME}".json s3://"${S3_BUCKET}"/"${ROLLING_SNAPSHOT_FILENAME}".json
            printf "%s Rolling Tezos : Metadata JSON ${ROLLING_SNAPSHOT_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

            # Rolling snapshot redirect object
            touch rolling

            # Upload rolling tezos snapshot redirect object
            if ! aws s3 cp rolling s3://"${S3_BUCKET}" --website-redirect /"${ROLLING_SNAPSHOT_FILENAME}" --cache-control 'no-cache'; then
                printf "%s Rolling Tezos : Error uploading redirect object for ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            else
                printf "%s Rolling Tezos : Sucessfully uploaded redirect object for ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            fi

            # Rolling snapshot json redirect file
            if ! touch rolling-snapshot-metadata; then
                printf "%s Rolling Snapshot : Error creating ${NETWORK}-rolling-snapshot-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            else
                printf "%s Rolling snapshot : Created ${NETWORK}-rolling-snapshot-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            fi

            # Upload rolling snapshot json redirect file and set header for previously uploaded rolling snapshot json File
            if ! aws s3 cp rolling-snapshot-metadata s3://"${S3_BUCKET}" --website-redirect /"${ROLLING_SNAPSHOT_FILENAME}".json --cache-control 'no-cache'; then
                printf "%s Rolling snapshot : Error uploading ${NETWORK}-rolling-snapshot-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            else
                printf "%s Rolling snapshot : Uploaded ${NETWORK}-rolling-snapshot-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            fi
        fi
    else
        printf "%s Rolling Tezos : ${ROLLING_SNAPSHOT} does not exist.  Not uploading.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
else
  printf "%s Skipping rolling snapshot import and export because this is an archive job.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

cd /srv/jekyll || exit

# Get latest values from JSONS

# TODO:
# - ONLY CURL ONCE
# - SHOULD ERROR?? WHY REDIRECT TO dev/null? JEKYLL FAILS IF CURL RETURNS HTML AND PUTS THAT INTO THE FILES
URL="http://${S3_BUCKET}.s3-website.us-east-1.amazonaws.com"

# clone https://github.com/oxheadalpha/xtz-shots-website
git clone https://github.com/oxheadalpha/xtz-shots-website

# cd to xtz-shots-website
cd xtz-shots-website || exit

curl -L $URL/archive-tarball-metadata -o _data/archive-tarball.json --create-dirs --silent
curl -L $URL/rolling-tarball-metadata -o _data/rolling-tarball-metadata.json --create-dirs --silent
curl -L $URL/rolling-snapshot-metadata -o _data/rolling-snapshot.json --create-dirs --silent

jq -n \
--arg NETWORK "$NETWORK" \
'{
  "network": $NETWORK
}' > tezos-metadata.json

# TODO: Can this be done in the container?
chmod -R 777 snapshot.md
chmod -R 777 _data
bundle exec jekyll build

# mv _site/snapshots/index.html to _site/index.html
mv _site/snapshot/* .

# upload index.html to website
if ! aws s3 cp _site/ s3://"${S3_BUCKET}" --recursive --include "*"; then
    printf "%s Website Build & Deploy : Error uploading site to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s Website Build & Deploy  : Sucessfully uploaded website to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi