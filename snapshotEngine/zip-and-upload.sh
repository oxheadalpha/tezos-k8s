#!/bin/bash

BLOCK_HEIGHT=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)
BLOCK_HASH=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH)
BLOCK_TIMESTAMP=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)
TEZOS_VERSION=$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/TEZOS_VERSION)
NETWORK="${NAMESPACE%%-*}"
export S3_BUCKET="${NETWORK}.${SNAPSHOT_WEBSITE_DOMAIN_NAME}"
export WEB_BUCKET="monosite.xtz-shots.io"

cd /

# If block_height is not set than init container failed, exit this container
[ -z "${BLOCK_HEIGHT}" ] && exit 1

printf "%s BLOCK_HASH is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HASH))\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
printf "%s BLOCK_HEIGHT is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_HEIGHT)\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
printf "%s BLOCK_TIMESTAMP is...$(cat /"${HISTORY_MODE}"-snapshot-cache-volume/BLOCK_TIMESTAMP)\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

#
# Archive Tarball
#

# Do not take archive tarball in rolling namespace
if [ "${HISTORY_MODE}" = archive ]; then
    printf "%s ********************* Archive Tarball *********************\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    ARCHIVE_TARBALL_FILENAME=tezos-"${NETWORK}"-archive-tarball-"${BLOCK_HEIGHT}".lz4
    printf "%s Archive tarball filename is ${ARCHIVE_TARBALL_FILENAME}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    # If you upload a file bigger than 50GB, you have to do a mulitpart upload with a part size between 1 and 10000.
    # Instead of guessing size, you can use expected-size which tells S3 how big the file is and it calculates the size for you.
    # However if the file gets bigger than your expected size, the multipart upload fails because it uses a part size outside of the bounds (1-10000)
    # This gets the old archive tarball size and then adds 10%.  Archive tarballs dont seem to grow more than that.
    if aws s3 ls s3://"${S3_BUCKET}" | grep archive-tarball-metadata; then #Use last file for expected size if it exists
        EXPECTED_SIZE=$(curl -L http://"${S3_BUCKET}"/archive-tarball-metadata 2>/dev/null | jq -r '.filesize_bytes' | awk '{print $1*1.1}' | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
    else
        EXPECTED_SIZE=100000000000 #100GB Arbitrary filesize for initial value. Only used if no archive-tarball-metadata exists. IE starting up test network
    fi

    # LZ4 /var/tezos/node selectively and upload to S3
    printf "%s Archive Tarball : Tarballing /var/tezos/node, LZ4ing, and uploading to S3...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > archive-tarball.sha256) \
    | aws s3 cp - s3://"${S3_BUCKET}"/"${ARCHIVE_TARBALL_FILENAME}" --expected-size "${EXPECTED_SIZE}"

    SHA256=$(cat archive-tarball.sha256)

    FILESIZE_BYTES=$(aws s3api head-object \
        --bucket "${S3_BUCKET}" \
        --key "${ARCHIVE_TARBALL_FILENAME}" \
        --query ContentLength \
        --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

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
        --arg URL "https://${S3_BUCKET}/${ARCHIVE_TARBALL_FILENAME}" \
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
            "filename": $ARCHIVE_TARBALL_FILENAME,
            "sha256": $SHA256,
            "url": $URL,
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
            printf "%s Archive Tarball : ${NETWORK}-archive-tarball created successfully.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        fi

        # Upload redirect file and set header for previously uploaded LZ4 File
        if ! aws s3 cp archive-tarball s3://"${S3_BUCKET}" --website-redirect /"${ARCHIVE_TARBALL_FILENAME}" --cache-control 'no-cache'; then
            printf "%s Archive Tarball : Error uploading ${NETWORK}-archive-tarball. to S3\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        else
            printf "%s Archive Tarball : Upload of ${NETWORK}-archive-tarball successful to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
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
    until [ -f "${ROLLING_SNAPSHOT}" ]; do
        printf "%s Waiting for ${ROLLING_SNAPSHOT} to exist...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        until [ -f "${ROLLING_SNAPSHOT}" ]; do
            if [ -f "${ROLLING_SNAPSHOT}" ];then
                break
            fi
        done
    done

    # Wait for rolling snapshot to import to temporary filesystem for tarball.
    # done

    while  [ -f "${IMPORT_IN_PROGRESS}" ]; do
        printf "%s Waiting for snapshot to import...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        while  [ -f "${IMPORT_IN_PROGRESS}" ]; do
            if ! [ -f "${IMPORT_IN_PROGRESS}" ]; then
                break
            fi
        done
    done



    # LZ4 /"${HISTORY_MODE}"-snapshot-cache-volume/var/tezos/node selectively and upload to S3
    printf "%s ********************* Rolling Tarball *********************\\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    # If you upload a file bigger than 50GB, you have to do a mulitpart upload with a part size between 1 and 10000.
    # Instead of guessing size, you can use expected-size which tells S3 how big the file is and it calculates the size for you.
    # However if the file gets bigger than your expected size, the multipart upload fails because it uses a part size outside of the bounds (1-10000)
    # This gets the old rolling tarball size and then adds 10%.  rolling tarballs dont seem to grow more than that.
    if aws s3 ls s3://"${S3_BUCKET}" | grep archive-tarball-metadata; then #Use last file for expected size if it exists
        EXPECTED_SIZE=$(curl -L http://"${S3_BUCKET}"/rolling-tarball-metadata 2>/dev/null | jq -r '.filesize_bytes' | awk '{print $1*1.1}' | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')
    else
        EXPECTED_SIZE=100000000000 #100GB Arbitrary filesize for initial value. Only used if no archive-tarball-metadata exists. IE starting up test network
    fi

    printf "%s Rolling Tarball : Tarballing /rolling-tarball-restore/var/tezos/node, LZ4ing, and uploading to S3...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    tar cvf - . \
    --exclude='node/data/identity.json' \
    --exclude='node/data/lock' \
    --exclude='node/data/peers.json' \
    --exclude='./lost+found' \
    -C /rolling-tarball-restore/var/tezos \
    | lz4 | tee >(sha256sum | awk '{print $1}' > rolling-tarball.sha256) \
    | aws s3 cp - s3://"${S3_BUCKET}"/"${ROLLING_TARBALL_FILENAME}" --expected-size "${EXPECTED_SIZE}"

    SHA256=$(cat rolling-tarball.sha256)

    FILESIZE_BYTES=$(aws s3api head-object \
    --bucket "${S3_BUCKET}" \
    --key "${ROLLING_TARBALL_FILENAME}" \
    --query ContentLength \
    --output text)
    FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs)

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
        --arg URL "https://${S3_BUCKET}/${ROLLING_TARBALL_FILENAME}" \
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
            "filename": $ROLLING_TARBALL_FILENAME,
            "url": $URL,
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
            printf "%s Rolling Tezos : Successfully uploaded ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            printf "%s Rolling Tezos : Uploading redirect...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

            FILESIZE_BYTES=$(stat -c %s "${ROLLING_SNAPSHOT}")
            printf "FILESIZE_BYTES COMMAND=%s\n" "$(stat -c %s "${ROLLING_SNAPSHOT}")"
            printf "FILESIZE_BYTES VARIABLE=%s\n" "${FILESIZE_BYTES}"

            FILESIZE=$(echo "${FILESIZE_BYTES}" | awk '{ suffix="KMGT"; for(i=0; $1>1024 && i < length(suffix); i++) $1/=1024; print int($1) substr(suffix, i, 1), $3; }' | xargs )
            SHA256=$(sha256sum "${ROLLING_SNAPSHOT}" | awk '{print $1}')

            jq -n \
            --arg BLOCK_HASH "$BLOCK_HASH" \
            --arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
            --arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
            --arg ROLLING_SNAPSHOT_FILENAME "$ROLLING_SNAPSHOT_FILENAME" \
            --arg URL "https://${S3_BUCKET}/${ROLLING_SNAPSHOT_FILENAME}" \
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
                "filename": $ROLLING_SNAPSHOT_FILENAME,
                "url": $URL,
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
                printf "%s Rolling Tezos : Successfully uploaded redirect object for ${ROLLING_SNAPSHOT} to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
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

# Need to be in this dir for jekyll to run.
# Container-specific requirement
cd /srv/jekyll || exit

# Copy Gemfile and Gemfile.lock to current dir
cp /snapshot-website-base/* .

# Grab latest metadata and put in _data
# if curl --fail -L "${S3_BUCKET}"/archive-tarball-metadata --silent > /dev/null; then
#     curl -L "${S3_BUCKET}"/archive-tarball-metadata -o _data/archive_tarball.json --create-dirs --silent
# fi

# if curl --fail -L "${S3_BUCKET}"/rolling-tarball-metadata --silent > /dev/null; then
#     curl -L "${S3_BUCKET}"/rolling-tarball-metadata -o _data/rolling_tarball.json --create-dirs --silent
# fi

# if curl --fail -L "${S3_BUCKET}"/rolling-snapshot-metadata --silent > /dev/null; then
#     curl -L "${S3_BUCKET}"/rolling-snapshot-metadata -o _data/rolling_snapshot.json --create-dirs --silent
# fi

# Store network name for liquid templating
# jq -n \
# --arg NETWORK "$NETWORK" \
# '{
#   "network": $NETWORK
# }' > _data/tezos_metadata.json

# Grab liquid-templated chain website page
curl -o index.md "${SNAPSHOT_MARKDOWN_TEMPLATE}"

# Update chain name for page title using variable
#sed -i'' -e 's/${NETWORK}/'"${NETWORK}"'/g' index.md

# Grab Jekyll config
curl -o _config.yml "${JEKYLL_CONFIG}"

# Add remote theme to config
cat <<EOF >> _config.yml
remote_theme: ${JEKYLL_REMOTE_THEME_REPOSITORY}
plugins:
- jekyll-remote-theme
EOF

git clone https://github.com/oxheadalpha/xtz-shots-website.git --branch monosite monosite

cp -r monosite/* .

rm -rf monosite

# Create snapshot.json
# List of all snapshot metadata accross all subdomains
# build site pages

python /updateAvailableSnapshotMetadata.py

# Check if snapshots.json exists
if [[ ! -f snapshots.json ]]; then
    printf "%s ERROR snapshots.json does not exist.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 5
    exit 1
fi

# Upload snapshots.json
if ! aws s3 cp snapshots.json s3://"${S3_BUCKET}"/snapshots.json; then
    printf "%s Upload snapshots.json : Error uploading file snapshots.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s Upload snapshots.json : File snapshots.json successfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

python /buildpages.py

chown -R jekyll:jekyll ./*
bundle exec jekyll build

# Upload chain page (index.html and assets) to root of website bucket
if ! aws s3 cp _site/ s3://"${WEB_BUCKET}" --recursive --include "*"; then
    printf "%s Website Build & Deploy : Error uploading site to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s Website Build & Deploy  : Successful uploaded website to S3.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

# Build base.json from existing metadata files

# Create new base.json locally
touch base.json
echo '[]' > "base.json"

printf "%s Building base.json... this may take a while.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
aws s3 ls s3://"${NETWORK}".xtz-shots.io |  grep '\.json'| sort | awk '{print $4}' | awk -F '\\\\n' '{print $1}' | tr ' ' '\n' | grep -v -e base.json -e snapshots.json | while read ITEM; do
    tmp=$(mktemp) && cp base.json "${tmp}" && jq --argjson file "$(curl -s https://"${NETWORK}".xtz-shots.io/$ITEM)" '. += [$file]' "${tmp}" > base.json
done

#Upload base.json
if ! aws s3 cp base.json s3://"${S3_BUCKET}"/base.json; then
    printf "%s Upload base.json : Error uploading file base.json to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s Upload base.json : File base.json successfully uploaded to S3.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi