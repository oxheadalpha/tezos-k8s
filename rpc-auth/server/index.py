import os
from urllib.parse import urljoin
from uuid import uuid4

import requests
from flask import Flask
from flask import request
from pytezos.crypto import Key
from redis import StrictRedis

TEZOS_CHAIN_ID = os.getenv("TEST_CHAIN_ID")
TEZOS_RPC = f"{os.getenv('TEZOS_RPC')}:{os.getenv('TEZOS_RPC_PORT')}"

app = Flask(__name__)
redis = StrictRedis(host=os.getenv("REDIS_HOST"), port=os.getenv("REDIS_PORT"))

## ROUTES


@app.route("/vending-machine/<chain_id>")
def get_nonce(chain_id):
    try:
        is_correct_chain_id = verify_chain_id(chain_id)
        if not is_correct_chain_id:
            return "Unauthorized", 401
    except requests.exceptions.RequestException as e:
        print("Failed to verify chain id.", e)
        return "Internal server error", 500

    # tz1 = request.values.get("tz1")
    # if not tz1:
    #     return make_response("Missing tz1 address", 400)

    nonce = create_nonce()
    redis.set(nonce, "", ex=3)
    return nonce


@app.route("/vending-machine")
def get_tezos_rpc_url():
    try:
        nonce, signature, public_key = [
            request.values[k] for k in ("nonce", "signature", "public_key")
        ]
    except KeyError as e:
        print("Request data:", request.values)
        print(e)
        return "Bad Request", 400

    if not is_valid_nonce(nonce):
        return "Unauthorized", 401

    # Immediately delete the nonce from redis so that it cannot be replayed.
    # (Will this actually prevent simultaneous requests with the same nonce??)
    # (May need to run a get/set in a transaction)
    redis.delete(nonce)

    is_valid_signature = verify_signature(public_key, signature, nonce)
    if not is_valid_signature:
        return "Unauthorized", 401

    secret_url = generate_secret_url(public_key)
    return secret_url


@app.route(
    "/tezos-node-rpc/<access_token>/<path:rpc_endpoint>",
    methods=["GET", "POST", "PATCH", "DELETE", "PUT"],
)
def rpc_passthrough(access_token, rpc_endpoint):
    if not is_valid_access_token(access_token):
        return "Unauthorized", 401

    request_method = getattr(requests, request.method.lower())
    return request_method(urljoin(f"http://{TEZOS_RPC}", rpc_endpoint)).text


## HELPER FUNCTIONS


def verify_chain_id(chain_id):
    global TEZOS_CHAIN_ID

    if not TEZOS_CHAIN_ID:
        TEZOS_CHAIN_ID = get_chain_id()
    if chain_id != TEZOS_CHAIN_ID:
        return False
    return True


def get_chain_id():
    response = requests.get(urljoin(f"http://{TEZOS_RPC}", "chains/main/chain_id"))
    return response.text.strip('\n"')


def create_nonce():
    return str(uuid4().hex)


def is_valid_nonce(nonce):
    if redis.get(nonce) != None:
        return True
    return False


def verify_signature(public_key, signature, nonce):
    try:
        bytes_prefix = "0x05"
        Key.from_encoded_key(public_key).verify(signature, bytes_prefix + nonce)
        return True
    except ValueError as e:
        print("Error verifying signature:", e)
        return False


def create_redis_access_token_key(access_token):
    return f"access_token:{access_token}"


def generate_secret_url(public_key):
    access_token = str(uuid4())
    redis.set(create_redis_access_token_key(access_token), public_key)
    return urljoin(request.url_root, f"tezos-node-rpc/{access_token}")


def is_valid_access_token(access_token):
    if redis.get(create_redis_access_token_key(access_token)) != None:
        return True
    return False


## Need a proper server for production
if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=8080,
        debug=(True if os.getenv("FLASK_ENV") == "development" else False),
    )
