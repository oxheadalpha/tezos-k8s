import os

BUCKET_NAME = os.getenv("BUCKET_NAME")
ENDPOINT_URL = os.getenv("HOST_BASE")
BUCKET_REGION_NAME = os.getenv("REGION_NAME")

PROTO_NAME = os.getenv("PROTO_NAME")

import boto3
s3 = boto3.resource('s3',
                    region_name=BUCKET_REGION_NAME,
                    endpoint_url=f"https://{ENDPOINT_URL}")

print(f"Downloading {PROTO_NAME}")
proto_file = f"/{PROTO_NAME}"
s3_bucket = s3.Bucket(BUCKET_NAME)
s3_bucket.download_file(PROTO_NAME, proto_file)
