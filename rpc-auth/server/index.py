import os
import re
import time
from functools import cache
from urllib.parse import urljoin
from uuid import uuid4

import requests
from flask import Flask, abort, request
from pytezos.crypto import Key
from redis import StrictRedis, WatchError

TEZOS_RPC_SERVICE_URL = (
    f"http://{os.getenv('TEZOS_RPC_SERVICE')}:{os.getenv('TEZOS_RPC_SERVICE_PORT')}"
)

app = Flask(__name__)
redis = StrictRedis(host=os.getenv("REDIS_HOST"), port=os.getenv("REDIS_PORT"))

## ROUTES


@app.route("/vending-machine/<chain_id>")
def get_nonce(chain_id):
    try:
        is_correct_chain_id = verify_chain_id(chain_id)
        if not is_correct_chain_id:
            abort(401)
    except requests.exceptions.RequestException as e:
        print("Failed to verify chain id.", e)
        abort(500)

    # Tezos client requires the data to be signed in hex format
    nonce = uuid4().hex
    redis.set(nonce, "", ex=3)
    return nonce


@app.route("/vending-machine", methods=["POST"])
def generate_tezos_rpc_url():
    try:
        nonce, signature, public_key = [
            request.values[k] for k in ("nonce", "signature", "public_key")
        ]
    except KeyError as e:
        print("Request data:", request.values)
        print(e)
        abort(400)

    if not is_valid_nonce(nonce):
        abort(401)

    tezos_key_object = get_tezos_key_object(public_key)
    if not is_valid_signature(tezos_key_object, signature, nonce):
        abort(401)

    access_token = uuid4().hex
    secret_url = create_secret_url(access_token)
    save_access_token(tezos_key_object.public_key_hash(), access_token)
    return secret_url


@app.route("/auth")
def rpc_auth():
    access_token = extract_access_token(request.headers)
    if not is_valid_access_token(access_token):
        abort(401)
    return "OK", 200


## HELPER FUNCTIONS


def verify_chain_id(chain_id):
    if chain_id != get_tezos_chain_id():
        return False
    return True


@cache
def get_tezos_chain_id():
    tezos_chain_id = os.getenv("TEZOS_CHAIN_ID")
    if tezos_chain_id:
        return tezos_chain_id
    chain_id_response = requests.get(
        urljoin(TEZOS_RPC_SERVICE_URL, "chains/main/chain_id")
    )
    return chain_id_response.text.strip('\n"')


def is_valid_nonce(nonce):
    with redis.pipeline() as pipeline:
        try:
            pipeline.watch(nonce)
            redis_nonce = pipeline.get(nonce)
            pipeline.multi()
            pipeline.delete(nonce)
            pipeline.execute()
            if redis_nonce != None:
                return True
        except WatchError:
            print("Nonce was already validated.")

        return False


def get_tezos_key_object(public_key):
    try:
        return Key.from_encoded_key(public_key)
    except ValueError as e:
        print("Something is wrong with the public_key provided:", e)
        abort(401)


def is_valid_signature(key_object, signature, nonce):
    try:
        bytes_prefix = "0x05"
        key_object.verify(signature, bytes_prefix + nonce)
        return True
    except ValueError as e:
        print("Error verifying signature:", e)
        return False


def create_secret_url(access_token):
    return urljoin(request.url_root, f"tezos-node-rpc/{access_token}")


def create_redis_access_token_key(access_token, hash=False):
    return f"access_token{':hash' if hash else ''}:{access_token}"


def save_access_token(tz_address, access_token):
    access_token_key = create_redis_access_token_key(access_token)
    with redis.pipeline() as pipeline:
        # Create redis hash of access token with timestamp and tz address
        pipeline.hset(
            access_token_key, mapping={"timestamp": time.time(), "address": tz_address}
        )
        # Add access token to list of this tz address's tokens
        pipeline.sadd(tz_address, access_token_key)
        pipeline.execute()


def extract_access_token(headers):
    original_url = headers.get("X-Original-Url")
    regex_obj = re.search(r"tezos-node-rpc/(.*?)/", original_url)
    if regex_obj:
        return regex_obj.group(1)


def is_valid_access_token(access_token):
    if (
        access_token
        and len(access_token) == 32  # Should be 32 char hex string
        and redis.exists(create_redis_access_token_key(access_token)) == 1
    ):
        return True
    return False


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8080,
        debug=(True if os.getenv("FLASK_ENV") == "development" else False),
    )
