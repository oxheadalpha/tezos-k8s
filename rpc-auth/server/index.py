from os import abort
from flask import Flask
from flask import request
from flask.helpers import make_response
from flask.wrappers import Response
# from markupsafe import escape
from pytezos.crypto import Key
from redis import Redis
import requests
from uuid import uuid4
import time

from requests.models import HTTPError

## See if there is a better way to inject these variables
CLUSTER_IP = "192.168.64.49"
# CLUSTER_CHAIN_ID = "NetXHFw7TkU5hhs"
CLUSTER_CHAIN_ID = None

app = Flask(__name__)
# redis_url = os.getenv('REDISTOGO_URL', 'redis://localhost:6379')
redis = Redis(host=CLUSTER_IP, port=6379)


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
        nonce, signature, pk = [
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
    redis.delete(nonce)

    is_valid_signature = verify_signature(pk, signature, nonce)
    if not is_valid_signature:
        return "Unauthorized", 401
    return "VERIFIED"


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
    nonce_from_redis = redis.get(nonce)
    if nonce_from_redis != None:
        return True
    return False


def verify_signature(pk, signature, nonce):
    try:
        bytes_prefix = "0x05"
        Key.from_encoded_key(pk).verify(signature, bytes_prefix + nonce)
        return True
    except ValueError as e:
        print("Error verifying signature:", e)
        return False


if __name__ == '__main__':
    app.run(host="localhost", port=8080, debug=True)
