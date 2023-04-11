import boto3
import os
import subprocess
import sys

BUCKET_NAME = os.environ["BUCKET_NAME"]
BUCKET_ENDPOINT_URL = os.environ["BUCKET_ENDPOINT_URL"]
BUCKET_REGION = os.environ["BUCKET_REGION"]

PROTO_NAME = os.environ["PROTO_NAME"]
VANITY_STRING = os.environ["VANITY_STRING"]

s3 = boto3.resource(
    "s3", region_name=BUCKET_REGION, endpoint_url=f"https://{BUCKET_ENDPOINT_URL}"
)

print(f"Downloading {PROTO_NAME}")
proto_file = f"/opt/{PROTO_NAME}"
s3_bucket = s3.Bucket(BUCKET_NAME)
try:
    s3_bucket.download_file(PROTO_NAME, proto_file)
except botocore.exceptions.ClientError as e:
    if e.response["Error"]["Code"] == "404":
        print("The object does not exist.")
        sys.exit(1)
    else:
        raise
cmd = subprocess.Popen(['/opt/tz-proto-vanity', f'/opt/{PROTO_NAME}', VANITY_STRING, '-f', 'csv'], stdout=subprocess.PIPE)
next(cmd.stdout) # ignore first line of csv
for line in cmd.stdout:
    linesplit = line.decode("utf-8").split(",")
    print(f"found vanity hash  {linesplit[0]} with nonce {linesplit[1]}")
    s3.Object(BUCKET_NAME, f"{PROTO_NAME}_{linesplit[0]}").put(Body=linesplit[1])
