from flask import Flask
from flask import request
from flask.helpers import make_response
from flask.wrappers import Response
from os import abort
from pytezos.crypto import Key
from redis import Redis
from uuid import uuid4
import requests

## See if there is a better way to inject these variables
CLUSTER_IP = "192.168.64.49"
# CLUSTER_CHAIN_ID = "NetXHFw7TkU5hhs"
CLUSTER_CHAIN_ID = None

app = Flask(__name__)
# redis_url = os.getenv('REDISTOGO_URL', 'redis://localhost:6379')
redis = Redis(host=CLUSTER_IP, port=6379)

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
def get_cluster_url():
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


@app.route("/tezos-node-rpc/<access_token>/<path:rpc_endpoint>",
           methods=["GET", "POST", "PATCH", "DELETE", "PUT"])
def rpc_passthrough(access_token, rpc_endpoint):
    if not is_valid_access_token(access_token):
        return "Unauthorized", 401

    request_method = getattr(requests, request.method.lower())
    return request_method(f"http://{CLUSTER_IP}/{rpc_endpoint}").text


## HELPER METHODS

def verify_chain_id(chain_id):
    global CLUSTER_CHAIN_ID

    if not CLUSTER_CHAIN_ID:
        CLUSTER_CHAIN_ID = get_chain_id()
    if chain_id != CLUSTER_CHAIN_ID:
        return False
    return True


def get_chain_id():
    response = requests.get(f"http://{CLUSTER_IP}/chains/main/chain_id")
    return response.text.strip('\n\"')


def create_nonce():
    return str(uuid4().hex)


def is_valid_nonce(nonce):
    if redis.get(nonce) != None:
        return True
    return False


def verify_signature(public_key, signature, nonce):
    try:
        bytes_prefix = "0x05"
        Key.from_encoded_key(public_key).verify(signature,
                                                bytes_prefix + nonce)
        return True
    except ValueError as e:
        print("Error verifying signature:", e)
        return False


def create_redis_access_token_key(access_token):
    return f"access_token:{access_token}"


def generate_secret_url(public_key):
    access_token = str(uuid4())
    redis.set(create_redis_access_token_key(access_token), public_key)
    return f"http://{CLUSTER_IP}/tezos-node-rpc/{access_token}"


def is_valid_access_token(access_token):
    if redis.get(create_redis_access_token_key(access_token)) != None:
        return True
    return False


if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8080)
