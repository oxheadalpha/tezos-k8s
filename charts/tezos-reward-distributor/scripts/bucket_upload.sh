#!/bin/sh

echo "Uploading TRD data to bucket"

source /trd/cfg/bucket_upload_secrets
if [ ! -z ${BUCKET_NAME} ];then
    aws s3  cp --recursive  /trd/ s3://${BUCKET_NAME}/${BAKER_NAME} --endpoint $BUCKET_ENDPOINT_URL
fi
sleep 10
