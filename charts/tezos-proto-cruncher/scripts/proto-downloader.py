import os

BUCKET_NAME = os.environ["BUCKET_NAME"]
BUCKET_ENDPOINT_URL = os.environ["BUCKET_ENDPOINT_URL"]
BUCKET_REGION = os.environ["BUCKET_REGION"]

PROTO_NAME = os.environ["PROTO_NAME"]

import boto3

s3 = boto3.resource(
    "s3", region_name=BUCKET_REGION, endpoint_url=f"https://{BUCKET_ENDPOINT_URL}"
)

print(f"Downloading {PROTO_NAME}")
proto_file = f"/{PROTO_NAME}"
s3_bucket = s3.Bucket(BUCKET_NAME)
try:
    s3_bucket.download_file(PROTO_NAME, proto_file)
except botocore.exceptions.ClientError as e:
    if e.response["Error"]["Code"] == "404":
        print("The object does not exist.")
    else:
        raise
