#!/bin/bash

BLOCK_HEIGHT=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)
BLOCK_HASH=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH)
BLOCK_TIMESTAMP=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)
#TEZOS_VERSION=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/TEZOS_VERSION)
NETWORK="${NAMESPACE%%-*}"
# Export for python
export S3_BUCKET="${NAMESPACE}"
TEZOS_RPC_VERSION_INFO="$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/TEZOS_RPC_VERSION_INFO)"

TEZOS_VERSION="$(echo "${TEZOS_RPC_VERSION_INFO}" | jq -r .version)"
TEZOS_VERSION_COMMIT_HASH="$(echo "${TEZOS_RPC_VERSION_INFO}" | jq -r .commit_info.commit_hash)"
TEZOS_VERSION_COMMIT_DATE="$(echo "${TEZOS_RPC_VERSION_INFO}" | jq -r .commit_info.commit_date)"

# Needed for alternate cloud providers
AWS_S3_BUCKET="${NAMESPACE%-*}.${SNAPSHOT_WEBSITE_DOMAIN_NAME}"

# Default to root, is overridden by below logic if CLOUD_PROVIDER is defined
# Used for redirect file that is always uploaded to AWS S3
REDIRECT_ROOT="/"

# CND Endpoint used for CDN URLs (different from command endpoint)
if [[ "${CLOUD_PROVIDER}" == "digitalocean" ]]; then
    FQDN=${S3_BUCKET}.nyc3.digitaloceanspaces.com
    URL="${FQDN}"
    REDIRECT_ROOT="https://${FQDN}/"
else
    URL="${S3_BUCKET}"
fi

cd /

# Sets aws command credentials depending on cloud provider
# Alias functionality outside of command blocks is not consistent
#  so we opted for this.
# $1 is file name
set_aws_command_creds(){
    if [[ $1 == "aws" ]]; then
        echo "AWS_ACCESS_KEY_ID=$(cat /aws-secrets/aws-access-id) \
            AWS_SECRET_ACCESS_KEY=$(cat /aws-secrets/aws-secret-key) \
            aws "
    else
        echo "AWS_ACCESS_KEY_ID=$(cat /do-secrets/do-spaces-access-id) \
            AWS_SECRET_ACCESS_KEY=$(cat /do-secrets/do-spaces-secret-key) \
            aws --endpoint-url https://nyc3.digitaloceanspaces.com "
    fi
}

# If block_height is not set than init container failed, exit this container
[[ -z "${BLOCK_HEIGHT}" ]] && exit 1

printf "%s BLOCK_HASH is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH))\n" "$(date "+%Y-%m-%d %H:%M:%S")"
printf "%s BLOCK_HEIGHT is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)\n" "$(date "+%Y-%m-%d %H:%M:%S")"
printf "%s BLOCK_TIMESTAMP is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)\n" "$(date "+%Y-%m-%d %H:%M:%S")"

#
# Archive Tarball
#

# Do not take archive tarball in rolling namespace
if [[ "${HISTORY_MODE}" = archive ]]; then
    printf "%s ********************* Archive Tarball *********************\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    ARCHIVE_TARBALL_FILENAME=tezos-"${NETWORK}"-archive-tarball-"${BLOCK_HEIGHT}".lz4
    printf "%s Archive tarball filename is ${ARCHIVE_TARBALL_FILENAME}\n" "$(date "+%Y-%m-%d %H:%M:%S")"

    # If you upload a file bigger than 50GB, you have to do a multipart upload with a part size between 1 and 10000.
    # Instead of guessing size, you can use expected-size which tells S3 how big the file is and it calculates the size for you.
    # However if the file gets bigger than your expected size, the multipart upload fails because it uses a part size outside of the bounds (1-10000)
    # This gets the old archive tarball size and then adds 10%.  Archive tarballs dont seem to grow more than that.
    if eval "$(set_aws_command_creds)" s3 ls s3://"${S3_BUCKET}" | grep archive-tarball-metadata; then #Use last file for expected size if it exists
        EXPECTED_SIZE=$(curl -L http://"${S3_BUCKET}"/archive-tarball-metadata 2>/dev/null | jq -r '.filesize_bytes' | awk '{print $1*1.1}' | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
    else
        EXPECTED_SIZE=1000000000000 #1000GB Arbitrary filesize for initial value. Only used if no archive-tarball-metadata exists. IE starting up test network
    fi

    # LZ4 /var/tezos/node selectively and upload to S3
    printf "%s Archive Tarball : Tarballing /var/tezos/node, LZ4ing, and uploading to S3...\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > archive-tarball.sha256) \
    | eval "$(set_aws_command_creds) s3 cp - s3://${S3_BUCKET}/${ARCHIVE_TARBALL_FILENAME} --expected-size ${EXPECTED_SIZE} --acl public-read"

    SHA256=$(cat archive-tarball.sha256)

    FILESIZE_BYTES=$(eval "$(set_aws_command_creds)" s3api head-object \
        --bucket "${S3_BUCKET}" \
        --key "${ARCHIVE_TARBALL_FILENAME}" \
        --query ContentLength \
        --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

    # Check if archive-tarball exists in S3 and process redirect
    if ! eval "$(set_aws_command_creds)" s3api head-object --bucket "${S3_BUCKET}" --key "${ARCHIVE_TARBALL_FILENAME}" > /dev/null; then
        printf "%s Archive Tarball : Error uploading ${ARCHIVE_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET}.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s Archive Tarball : Upload of ${ARCHIVE_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET} successful!\n" "$(date "+%Y-%m-%d %H:%M:%S")"

        # Create archive tarball metadata json
        jq -n \
        --arg BLOCK_HASH "${BLOCK_HASH}" \
        --arg BLOCK_HEIGHT "${BLOCK_HEIGHT}" \
        --arg BLOCK_TIMESTAMP "${BLOCK_TIMESTAMP}" \
        --arg ARCHIVE_TARBALL_FILENAME "${ARCHIVE_TARBALL_FILENAME}" \
        --arg URL "https://${URL}/${ARCHIVE_TARBALL_FILENAME}" \
        --arg SHA256 "${SHA256}" \
        --arg FILESIZE_BYTES "${FILESIZE_BYTES}" \
        --arg FILESIZE "${FILESIZE}" \
        --arg NETWORK "${NETWORK}" \
        --arg HISTORY_MODE "archive" \
        --arg ARTIFACT_TYPE "tarball" \
        --arg TEZOS_VERSION_COMMIT_HASH "${TEZOS_VERSION_COMMIT_HASH}" \
        --arg TEZOS_VERSION_COMMIT_DATE "${TEZOS_VERSION_COMMIT_DATE}" \
        '{
            "block_hash": $BLOCK_HASH,
            "block_height": ($BLOCK_HEIGHT|fromjson),
            "block_timestamp": $BLOCK_TIMESTAMP,
            "filename": $ARCHIVE_TARBALL_FILENAME,
            "url": $URL,
            "sha256": $SHA256,
            "filesize_bytes": ($FILESIZE_BYTES|fromjson),
            "filesize": $FILESIZE,
            "chain_name": $NETWORK,
            "history_mode": $HISTORY_MODE,
            "artifact_type": $ARTIFACT_TYPE,
            "tezos_version": {
                "implementation": "octez",
                "version": "",
                "commit_info": {
                    "commit_hash": $TEZOS_VERSION_COMMIT_HASH,
                    "commit_date": $TEZOS_VERSION_COMMIT_DATE
                }
            }
        }' \
        > "${ARCHIVE_TARBALL_FILENAME}".json

        # Since version.additional_info will either be another object or "release" we just overwrite it from whatever we got above
        # JQ has trouble inserting a key into a file this is the way we opted to insert it
        tmp=$(mktemp)
        jq --arg version "$TEZOS_VERSION" '.tezos_version.version = ($version|fromjson)' "${ARCHIVE_TARBALL_FILENAME}".json > "$tmp" && mv "$tmp" "${ARCHIVE_TARBALL_FILENAME}".json

        # Check metadata json exists
        if [[ -s "${ARCHIVE_TARBALL_FILENAME}".json ]]; then
            printf "%s Archive Tarball : ${ARCHIVE_TARBALL_FILENAME}.json created.\n" "$(date "+%Y-%m-%d %H:%M:%S")"

            # Upload archive tarball metadata json
            if ! eval "$(set_aws_command_creds)"  s3 cp "${ARCHIVE_TARBALL_FILENAME}".json s3://"${S3_BUCKET}"/"${ARCHIVE_TARBALL_FILENAME}".json --acl public-read; then
                printf "%s Archive Tarball : Error uploading ${ARCHIVE_TARBALL_FILENAME}.json to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            else
                printf "%s Archive Tarball : Artifact JSON ${ARCHIVE_TARBALL_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi
        else
            printf "%s Archive Tarball : Error creating ${ARCHIVE_TARBALL_FILENAME}.json.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Create archive tarball redirect file
        if ! touch archive-tarball; then
            printf "%s Archive Tarball : Error creating ${NETWORK}-archive-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Archive Tarball : ${NETWORK}-archive-tarball created successfully.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Upload redirect file and set header for previously uploaded LZ4 File
        if ! eval "$(set_aws_command_creds "aws")" s3 cp archive-tarball s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ARCHIVE_TARBALL_FILENAME}" --cache-control 'no-cache'; then
            printf "%s Archive Tarball : Error uploading ${NETWORK}-archive-tarball. to S3\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Archive Tarball : Upload of ${NETWORK}-archive-tarball successful to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Archive Tarball json redirect file
        if ! touch archive-tarball-metadata; then
            printf "%s Archive Tarball : Error creating ${NETWORK}-archive-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Archive Tarball : Created ${NETWORK}-archive-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Upload archive tarball json redirect file and set header for previously uploaded archive tarball json File
        if ! eval "$(set_aws_command_creds "aws")" s3 cp archive-tarball-metadata s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ARCHIVE_TARBALL_FILENAME}".json --cache-control 'no-cache'; then
            printf "%s archive Tarball : Error uploading ${NETWORK}-archive-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s archive Tarball : Uploaded ${NETWORK}-archive-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi
    fi
else
    printf "%s Archive Tarball : Not creating archive tarball since this is a rolling job.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
fi

# Rolling artifacts for rolling history mode
if [ "${HISTORY_MODE}" = rolling ]; then

    # Rolling snapshot and tarball vars
    ROLLING_SNAPSHOT_FILENAME="${NETWORK}"-"${BLOCK_HEIGHT}".rolling
    ROLLING_SNAPSHOT=/"${HISTORY_MODE}"-snapshot-cache-volume/"${ROLLING_SNAPSHOT_FILENAME}"
    ROLLING_TARBALL_FILENAME=tezos-"${NETWORK}"-rolling-tarball-"${BLOCK_HEIGHT}".lz4
    IMPORT_IN_PROGRESS=/rolling-tarball-restore/snapshot-import-in-progress

    # Wait for rolling snapshot file
    until [ -f "${ROLLING_SNAPSHOT}" ]; do
        printf "%s Waiting for ${ROLLING_SNAPSHOT} to exist...\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        until [ -f "${ROLLING_SNAPSHOT}" ]; do
            if [ -f "${ROLLING_SNAPSHOT}" ];then
                break
            fi
        done
    done

    # Errors if above loop is broken out of but for some reason rolling snapshot doesnt exist
    if [ -f "${ROLLING_SNAPSHOT}" ]; then
        printf "%s ${ROLLING_SNAPSHOT} exists!\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s ERROR ##### ${ROLLING_SNAPSHOT} does not exist!\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        sleep 10
        exit 1
    fi

    # Needs time in between checks. This is faster than the snapshot container can create and delete the import files
    sleep 10s

    # Wait for rolling snapshot to import to temporary filesystem for tarball.
    while [ -f "${IMPORT_IN_PROGRESS}" ]; do
        printf "%s Waiting for snapshot to import...\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        while  [ -f "${IMPORT_IN_PROGRESS}" ]; do
            if ! [ -f "${IMPORT_IN_PROGRESS}" ]; then
                break
            fi
        done
    done

    # Errors if above loop is broken out of but for some reason import_in_progress_file still exists
    if ! [ -f "${IMPORT_IN_PROGRESS}" ]; then
        printf "%s Snapshot import finished!\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s ERROR ##### Snapshot import did not finish!\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        sleep 10
        exit 1
    fi

    # LZ4 /"${HISTORY_MODE}"-snapshot-cache-volume/var/tezos/node selectively and upload to S3
    printf "%s ********************* Rolling Tarball *********************\\n" "$(date "+%Y-%m-%d %H:%M:%S")"

    # If you upload a file bigger than 50GB, you have to do a multipart upload with a part size between 1 and 10000.
    # Instead of guessing size, you can use expected-size which tells S3 how big the file is and it calculates the size for you.
    # However if the file gets bigger than your expected size, the multipart upload fails because it uses a part size outside of the bounds (1-10000)
    # This gets the old rolling tarball size and then adds 10%.  rolling tarballs dont seem to grow more than that.
    printf "%s Rolling Tarball: Getting last rolling tarball filesize for multipart upload...\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    if eval "$(set_aws_command_creds "aws")" s3 ls s3://"${S3_BUCKET}" | grep rolling-tarball-metadata; then #Use last file for expected size if it exists
        EXPECTED_SIZE=$(curl -L http://"${S3_BUCKET}"/rolling-tarball-metadata 2>/dev/null | jq -r '.filesize_bytes' | awk '{print $1*1.1}' | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
        printf "%s Rolling Tarball: Bucket has existing artifact metadata.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
        printf "%s Rolling Tarball: Expected size is - %s  \n" "$(date "+%Y-%m-%d %H:%M:%S")" "${EXPECTED_SIZE}"
    else
        EXPECTED_SIZE=100000000000 #100GB Arbitrary filesize for initial value. Only used if no rolling-tarball-metadata exists. IE starting up test network
        printf "%s Rolling Tarball: No existing rolling tarball metadata...  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
        printf "%s Rolling Tarball: Expected size set arbitrarily to %s...  \n" "$(date "+%Y-%m-%d %H:%M:%S")" "${EXPECTED_SIZE}"
    fi

    printf "%s Rolling Tarball : Tarballing /rolling-tarball-restore/var/tezos/node, LZ4ing, and uploading to %s S3 bucket %s.\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$([[ -n ${CLOUD_PROVIDER} ]] && echo ${CLOUD_PROVIDER} || echo aws)" "${S3_BUCKET}"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /rolling-tarball-restore/var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > rolling-tarball.sha256) \
    | eval "$(set_aws_command_creds) s3 cp - s3://${S3_BUCKET}/${ROLLING_TARBALL_FILENAME} --expected-size ${EXPECTED_SIZE} --acl public-read" 


    SHA256=$(cat rolling-tarball.sha256)

    FILESIZE_BYTES=$(eval "$(set_aws_command_creds)" s3api head-object \
    --bucket "${S3_BUCKET}" \
    --key "${ROLLING_TARBALL_FILENAME}" \
    --query ContentLength \
    --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

    # Check if rolling-tarball exists and process redirect
    if ! eval "$(set_aws_command_creds)" s3api head-object --bucket "${S3_BUCKET}" --key "${ROLLING_TARBALL_FILENAME}" > /dev/null; then
        printf "%s Rolling Tarball : Error uploading ${ROLLING_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET}.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s Rolling Tarball : Upload of ${ROLLING_TARBALL_FILENAME} to S3 Bucket ${S3_BUCKET} successful!\n" "$(date "+%Y-%m-%d %H:%M:%S")"

        jq -n \
        --arg BLOCK_HASH "$BLOCK_HASH" \
        --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
        --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
        --arg ROLLING_TARBALL_FILENAME "$ROLLING_TARBALL_FILENAME" \
        --arg URL "https://${URL}/${ROLLING_TARBALL_FILENAME}" \
        --arg SHA256 "$SHA256" \
        --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
        --arg FILESIZE "$FILESIZE" \
        --arg NETWORK "$NETWORK" \
        --arg HISTORY_MODE "rolling" \
        --arg ARTIFACT_TYPE "tarball" \
        --arg TEZOS_VERSION_COMMIT_HASH "${TEZOS_VERSION_COMMIT_HASH}" \
        --arg TEZOS_VERSION_COMMIT_DATE "${TEZOS_VERSION_COMMIT_DATE}" \
        '{
            "block_hash": $BLOCK_HASH,
            "block_height": ($BLOCK_HEIGHT|fromjson),
            "block_timestamp": $BLOCK_TIMESTAMP,
            "filename": $ROLLING_TARBALL_FILENAME,
            "url": $URL,
            "sha256": $SHA256,
            "filesize_bytes": ($FILESIZE_BYTES|fromjson),
            "filesize": $FILESIZE,
            "chain_name": $NETWORK,
            "history_mode": $HISTORY_MODE,
            "artifact_type": $ARTIFACT_TYPE,
            "tezos_version": {
                "implementation": "octez",
                "version": "",
                "commit_info": {
                    "commit_hash": $TEZOS_VERSION_COMMIT_HASH,
                    "commit_date": $TEZOS_VERSION_COMMIT_DATE
                }
            }
        }' \
        > "${ROLLING_TARBALL_FILENAME}".json

        # Since version.additional_info will either be another object or "release" we just overwrite it from whatever we got above
        # JQ has trouble inserting a key into a file this is the way we opted to insert it
        tmp=$(mktemp)
        jq --arg version "$TEZOS_VERSION" '.tezos_version.version = ($version|fromjson)' "${ROLLING_TARBALL_FILENAME}".json > "$tmp" && mv "$tmp" "${ROLLING_TARBALL_FILENAME}".json
        
        # Check metadata exists
        if [[ -s "${ROLLING_TARBALL_FILENAME}".json ]]; then
            printf "%s Rolling Tarball : ${ROLLING_TARBALL_FILENAME}.json created.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            
            # upload metadata json
            if ! eval "$(set_aws_command_creds)" s3 cp "${ROLLING_TARBALL_FILENAME}".json s3://"${S3_BUCKET}"/"${ROLLING_TARBALL_FILENAME}".json --acl public-read; then
                printf "%s Rolling Tarball : Error uploading ${ROLLING_TARBALL_FILENAME}.json to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            else
                printf "%s Rolling Tarball : Metadata JSON ${ROLLING_TARBALL_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi
        else
            printf "%s Rolling Tarball : Error creating ${ROLLING_TARBALL_FILENAME}.json locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi
        
        # Tarball redirect file
        if ! touch rolling-tarball; then
            printf "%s Rolling Tarball : Error creating ${NETWORK}-rolling-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Rolling Tarball : Created ${NETWORK}-rolling-tarball file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Upload redirect file and set header for previously uploaded LZ4 File
        if ! eval "$(set_aws_command_creds "aws")" s3 cp rolling-tarball s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ROLLING_TARBALL_FILENAME}" --cache-control 'no-cache'; then
            printf "%s Rolling Tarball : Error uploading ${NETWORK}-rolling-tarball file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Rolling Tarball : Uploaded ${NETWORK}-rolling-tarball file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Rolling Tarball json redirect file
        if ! touch rolling-tarball-metadata; then
            printf "%s Rolling Tarball : Error creating ${NETWORK}-rolling-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Rolling Tarball : Created ${NETWORK}-rolling-tarball-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi

        # Upload rolling tarball json redirect file and set header for previously uploaded rolling tarball json File
        if ! eval "$(set_aws_command_creds "aws")" s3 cp rolling-tarball-metadata s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ROLLING_TARBALL_FILENAME}".json --cache-control 'no-cache'; then
            printf "%s Rolling Tarball : Error uploading ${NETWORK}-rolling-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Rolling Tarball : Uploaded ${NETWORK}-rolling-tarball-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        fi
    fi

    #
    # Rolling Snapshot
    #
    printf "%s ********************* Rolling Tezos Snapshot *********************\\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    # If rolling snapshot exists locally
    if test -f "${ROLLING_SNAPSHOT}"; then
        printf "%s ${ROLLING_SNAPSHOT} exists!\n" "$(date "+%Y-%m-%d %H:%M:%S")"

        # Upload rolling snapshot to S3 and error on failure
        if ! eval "$(set_aws_command_creds)" s3 cp "${ROLLING_SNAPSHOT}" s3://"${S3_BUCKET}" --acl public-read; then
            printf "%s Rolling Tezos : Error uploading ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
        else
            printf "%s Rolling Tezos : Successfully uploaded ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"

            printf "%s Rolling Tezos : Uploading redirect...\n" "$(date "+%Y-%m-%d %H:%M:%S")"

            FILESIZE_BYTES=$(stat -c %s "${ROLLING_SNAPSHOT}")
            printf "FILESIZE_BYTES COMMAND=%s\n" "$(stat -c %s "${ROLLING_SNAPSHOT}")"
            printf "FILESIZE_BYTES VARIABLE=%s\n" "${FILESIZE_BYTES}"

            FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs )
            SHA256=$(sha256sum "${ROLLING_SNAPSHOT}" | awk '{print $1}')
            
            TEZOS_VERSION_MAJOR="$(echo "${TEZOS_RPC_VERSION_INFO}" | jq .version.major)"

            if [[ $TEZOS_VERSION_MAJOR -lt 16 ]]; then
                SNAPSHOT_VERSION=4
            else
                SNAPSHOT_HEADER=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/SNAPSHOT_HEADER)
                SNAPSHOT_VERSION="$(echo "${SNAPSHOT_HEADER}" | jq .snapshot_header.version)"
            fi

            jq -n \
            --arg BLOCK_HASH "$BLOCK_HASH" \
            --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
            --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
            --arg ROLLING_SNAPSHOT_FILENAME "$ROLLING_SNAPSHOT_FILENAME" \
            --arg URL "https://${URL}/${ROLLING_SNAPSHOT_FILENAME}" \
            --arg SHA256 "$SHA256" \
            --arg FILESIZE_BYTES "$FILESIZE_BYTES" \
            --arg FILESIZE "$FILESIZE" \
            --arg NETWORK "$NETWORK" \
            --arg HISTORY_MODE "rolling" \
            --arg ARTIFACT_TYPE "tezos-snapshot" \
            --arg TEZOS_VERSION_COMMIT_HASH "${TEZOS_VERSION_COMMIT_HASH}" \
            --arg TEZOS_VERSION_COMMIT_DATE "${TEZOS_VERSION_COMMIT_DATE}" \
            --arg SNAPSHOT_VERSION "$SNAPSHOT_VERSION" \
            '{
                "block_hash": $BLOCK_HASH,
                "block_height": ($BLOCK_HEIGHT|fromjson),
                "block_timestamp": $BLOCK_TIMESTAMP,
                "filename": $ROLLING_SNAPSHOT_FILENAME,
                "url": $URL,
                "sha256": $SHA256,
                "filesize_bytes": ($FILESIZE_BYTES|fromjson),
                "filesize": $FILESIZE,
                "chain_name": $NETWORK,
                "history_mode": $HISTORY_MODE,
                "artifact_type": $ARTIFACT_TYPE,
                "tezos_version":{
                    "implementation": "octez",
                    "version": "",
                    "commit_info": {
                        "commit_hash": $TEZOS_VERSION_COMMIT_HASH,
                        "commit_date": $TEZOS_VERSION_COMMIT_DATE
                    }
                },
                "snapshot_version": ($SNAPSHOT_VERSION|fromjson),
            }' \
            > "${ROLLING_SNAPSHOT_FILENAME}".json

            # Since version.additional_info will either be another object or "release" we just overwrite it from whatever we got above
            # JQ has trouble inserting a key into a file this is the way we opted to insert it
            tmp=$(mktemp)
            jq --arg version "$TEZOS_VERSION" '.tezos_version.version = ($version|fromjson)' "${ROLLING_SNAPSHOT_FILENAME}".json > "$tmp" && mv "$tmp" "${ROLLING_SNAPSHOT_FILENAME}".json

            # Check metadata json exists
            if [[ -s "${ROLLING_SNAPSHOT_FILENAME}".json ]]; then
                printf "%s Rolling Snapshot : ${ROLLING_SNAPSHOT_FILENAME}.json created.\n" "$(date "+%Y-%m-%d %H:%M:%S")"

                # Upload Rolling Snapshot metadata json
                if ! eval "$(set_aws_command_creds)" s3 cp "${ROLLING_SNAPSHOT_FILENAME}".json s3://"${S3_BUCKET}"/"${ROLLING_SNAPSHOT_FILENAME}".json --acl public-read; then
                    printf "%s Rolling Snapshot : Error uploading ${ROLLING_SNAPSHOT_FILENAME}.json to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
                else
                    printf "%s Rolling Snapshot : Artifact JSON ${ROLLING_SNAPSHOT_FILENAME}.json uploaded to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
                fi
            else
                printf "%s Rolling Snapshot : Error creating ${ROLLING_SNAPSHOT_FILENAME}.json.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi

            # Rolling snapshot redirect object
            touch rolling

            # Upload rolling tezos snapshot redirect object
            if ! eval "$(set_aws_command_creds "aws")" s3 cp rolling s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ROLLING_SNAPSHOT_FILENAME}" --cache-control 'no-cache'; then
                printf "%s Rolling Tezos : Error uploading redirect object for ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            else
                printf "%s Rolling Tezos : Successfully uploaded redirect object for ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi

            # Rolling snapshot json redirect file
            if ! touch rolling-snapshot-metadata; then
                printf "%s Rolling Snapshot : Error creating ${NETWORK}-rolling-snapshot-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            else
                printf "%s Rolling snapshot : Created ${NETWORK}-rolling-snapshot-metadata file locally.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi

            # Upload rolling snapshot json redirect file and set header for previously uploaded rolling snapshot json File
            if ! eval "$(set_aws_command_creds "aws")" s3 cp rolling-snapshot-metadata s3://"${AWS_S3_BUCKET}" --website-redirect "${REDIRECT_ROOT}${ROLLING_SNAPSHOT_FILENAME}".json --cache-control 'no-cache'; then
                printf "%s Rolling snapshot : Error uploading ${NETWORK}-rolling-snapshot-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            else
                printf "%s Rolling snapshot : Uploaded ${NETWORK}-rolling-snapshot-metadata file to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
            fi
        fi
    else
        printf "%s Rolling Tezos : ${ROLLING_SNAPSHOT} does not exist.  Not uploading.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
    fi
else
  printf "%s Skipping rolling snapshot import and export because this is an archive job.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
fi

if [[ -n "${SNAPSHOT_WEBSITE_DOMAIN_NAME}" ]]; then

    # Network bucket redirect
    # Redirects from network.website.com to website.com/network
    touch index.html
    if ! eval "$(set_aws_command_creds "aws")" s3 cp index.html s3://"${AWS_S3_BUCKET}" --website-redirect https://"${SNAPSHOT_WEBSITE_DOMAIN_NAME}"/"${NETWORK}" --cache-control 'no-cache'; then
        printf "%s ERROR ##### Could not upload network site redirect.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s Successfully uploaded network site redirect.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    fi

    # Need to be in this dir for jekyll to run.
    # Container-specific requirement
    cd /srv/jekyll || exit

    # Copy Gemfile and Gemfile.lock to current dir
    cp /snapshot-website-base/* .

    # Remote theme does not work
    # Using git instead
    REPO="${JEKYLL_REMOTE_THEME_REPOSITORY%@*}"
    BRANCH="${JEKYLL_REMOTE_THEME_REPOSITORY#*@}"
    LOCAL_DIR=monosite
    git clone https://github.com/"${REPO}".git --branch "${BRANCH}" "${LOCAL_DIR}"
    cp -r "${LOCAL_DIR}"/* .
    rm -rf "${LOCAL_DIR}"

    # Create new base.json locally
    touch base.json
    echo '[]' > "base.json"

    printf "%s Building base.json... this may take a while.\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    eval "$(set_aws_command_creds)" s3 ls s3://"${S3_BUCKET}" |  grep '\.json'| sort | awk '{print $4}' | awk -F '\\\\n' '{print $1}' | tr ' ' '\n' | grep -v -e base.json -e tezos-snapshots.json | while read ITEM; do
        tmp=$(mktemp) && cp base.json "${tmp}" && jq --argjson file "$(curl -s https://"${FQDN}"/$ITEM)" '. += [$file]' "${tmp}" > base.json
    done

    #Upload base.json
    if ! eval "$(set_aws_command_creds)" s3 cp base.json s3://"${S3_BUCKET}"/base.json --acl public-read; then
        printf "%s Upload base.json : Error uploading file base.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s Upload base.json : File base.json successfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
    fi

    # Create snapshot.json
    # List of all snapshot metadata across all subdomains
    # build site pages
    python /getAllSnapshotMetadata.py

    # Fail if python raised exception (validation failure)
    ret=$?
    if [[ "${ret}" -ne 0 ]]; then
        printf "%s Metadata did not validate sucessfully. Exiting...  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
        sleep 20
        exit 1
    fi

    # Check if tezos-snapshots.json exists
    # tezos-snapshots.json is a list of all snapshots in all buckets
    if [[ ! -f tezos-snapshots.json ]]; then
        printf "%s ERROR tezos-snapshots.json does not exist locally.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
        sleep 5
        exit 1
    fi

    # Upload tezos-snapshots.json
    if ! eval "$(set_aws_command_creds "aws")" s3 cp tezos-snapshots.json s3://"${SNAPSHOT_WEBSITE_DOMAIN_NAME}"/tezos-snapshots.json; then
        printf "%s Upload tezos-snapshots.json : Error uploading file tezos-snapshots.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
    else
        printf "%s Upload tezos-snapshots.json : File tezos-snapshots.json successfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S")"
    fi

    # Separate python for web page build
    # Needs tezos-snapshots.json to exist before pages are built
    python /getLatestSnapshotMetadata.py

    # Generate HTML from markdown and metadata
    chown -R jekyll:jekyll ./*
    bundle exec jekyll build --quiet

    # Upload chain page (index.html and assets) to root of website bucket
    eval "$(set_aws_command_creds "aws")" s3 cp _site/ s3://"${SNAPSHOT_WEBSITE_DOMAIN_NAME}" --recursive | grep "*"

    exit 0
fi