#!/bin/sh

echo "Uploading TRD data to bucket"

if [ ! -z ${BUCKET_NAME} ];then
    export AWS_SECRET_ACCESS_KEY=$(cat /trd/config/aws_secret_access_key)
    aws s3  cp --recursive  /trd/ s3://${BUCKET_NAME}/${BAKER_NAME} --endpoint $BUCKET_ENDPOINT_URL
fi
sleep 10
