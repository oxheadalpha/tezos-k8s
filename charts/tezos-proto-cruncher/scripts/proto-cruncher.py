import hashlib
import random
import base58
import string
import os
import sys
import re


proto_file = sys.argv[1]

def tb(l):
    return b''.join(map(lambda x: x.to_bytes(1, 'big'), l))
proto_prefix = tb([2, 170])

PROTO_NAME = os.getenv("PROTO_NAME")
VANITY_STRING = os.getenv("VANITY_STRING")
BUCKET_NAME = os.getenv("BUCKET_NAME")
BUCKET_ENDPOINT_URL = os.getenv("BUCKET_ENDPOINT_URL")
BUCKET_REGION = os.getenv("BUCKET_REGION")

if BUCKET_NAME:
    import boto3
    s3 = boto3.resource('s3',
                        region_name=BUCKET_REGION,
                        endpoint_url=f"https://{BUCKET_ENDPOINT_URL}")

with open(proto_file, "rb") as f:
    proto_bytes = f.read()

with open(proto_file, "rb") as f:
    proto_lines = f.readlines()


# For speed, we precompute the hash of the proto without the last line
# containing the vanity nonce.
# Later on, we add the last line and recompute.
# This speeds up the brute force by a large factor, compared to hashing
# in full at every try.
original_nonce = proto_lines[-1]
# First 4 bytes are truncated (not used in proto hashing)
proto_hash = hashlib.blake2b(proto_bytes[4:][:-len(original_nonce)], digest_size=32)

def get_hash(vanity_nonce, proto_hash):
    proto_hash.update(vanity_nonce)
    return base58.b58encode_check(proto_prefix + proto_hash.digest()).decode('utf-8')

print(f"Original proto nonce: {original_nonce} and hash: {get_hash(original_nonce, proto_hash.copy())}")

while True:
    # Warning - assuming the nonce is 16 chars in the original proto.
    # If it is not, set the current number below, otherwise you will get bad nonces.
    new_nonce_digits = ''.join(random.choice(string.digits) for _ in range(16))
    new_nonce = b'(* Vanity nonce: ' + bytes(new_nonce_digits, 'utf-8') + b' *)\n'

    new_hash = get_hash(new_nonce, proto_hash.copy())
    if re.match(f"^{VANITY_STRING}.*", new_hash):
        print(f"Found vanity nonce: {new_nonce} and hash: {new_hash}")
        if BUCKET_NAME:
            s3.Object(BUCKET_NAME, f"{PROTO_NAME}_{new_hash}").put(Body=new_nonce)
