import os

BUCKET_NAME = os.getenv("BUCKET_NAME")
BUCKET_ENDPOINT_URL = os.getenv("BUCKET_ENDPOINT_URL")
BUCKET_REGION= os.getenv("BUCKET_REGION")

PROTO_NAME = os.getenv("PROTO_NAME")

import boto3
s3 = boto3.resource('s3',
                    region_name=BUCKET_REGION,
                    endpoint_url=f"https://{BUCKET_ENDPOINT_URL}")

print(f"Downloading {PROTO_NAME}")
proto_file = f"/{PROTO_NAME}"
s3_bucket = s3.Bucket(BUCKET_NAME)
s3_bucket.download_file(PROTO_NAME, proto_file)
