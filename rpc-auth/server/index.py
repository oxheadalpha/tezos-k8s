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
# CHAIN_ID = "NetXHFw7TkU5hhs"
CHAIN_ID = None

app = Flask(__name__)
# redis_url = os.getenv('REDISTOGO_URL', 'redis://localhost:6379')
redis = Redis(host=CLUSTER_IP, port=6379)


@app.route("/vending-machine/<chain_id>")
def get_nonce(chain_id):
    try:
      is_correct_chain_id = verify_chain_id(chain_id)
      if not is_correct_chain_id:
          return make_response("Unauthorized", 401)
    except requests.exceptions.RequestException as e:
      print("Failed to verify chain id", e)
      return "Internal server error", 500

    # tz1 = request.values.get("tz1")
    # if not tz1:
    #     return make_response("Missing tz1 address", 400)

    nonce = create_nonce()
    redis.set(nonce, 0, ex=3)
    return nonce


@app.route("/vending-machine")
def get_cluster_url():
    nonce, signature, pk = [
        request.values[k] for k in ("nonce", "signature", "public_key")
    ]

    ### error handle values

    nonce_access_count = int(redis.get(nonce))
    if nonce_access_count != 0:
        return "Unauthorized", 401

    # Set nonce's access count to 1 so that it cannot be replayed
    redis.set(nonce, 1, xx=True, keepttl=True)

    is_valid_signature = verify_signature(pk, signature, nonce)
    if not is_valid_signature:
        return "Unauthorized", 401
    return "VERIFIED"


def verify_chain_id(chain_id):
    global CHAIN_ID

    if not CHAIN_ID:
        CHAIN_ID = get_chain_id()
    if chain_id != CHAIN_ID:
        return False
    return True


def get_chain_id():
    response = requests.get(f"http://{CLUSTER_IP}/chains/main/chain_id")
    return response.text.strip('\n\"')

def create_nonce():
    return str(uuid4().hex)


def verify_signature(pk, signature, nonce):
    try:
        bytes_prefix = "0x05"
        Key.from_encoded_key(pk).verify(signature, bytes_prefix + nonce)
        return True
    except ValueError:
        return False


if __name__ == '__main__':
    app.run(host="localhost", port=8080, debug=True)
