"""Get the public key hashes of the accounts provided via the signer's
ConfigMap. Create json objects with the hashes as the keys and write them to
keys.json. The signer will read the file to determine keys it is signing for."""

import json
import logging
import sys
from os import path

from pytezos import Key

config_path = "./signer-config"
accounts_json_path = f"{config_path}/accounts.json"

if not path.isfile(accounts_json_path):
    logging.warning("accounts.json file not found. Exiting.")
    sys.exit(0)

keys = {}

with open(accounts_json_path, "r") as accounts_file:
    accounts = json.load(accounts_file)
    for account in accounts:
        key = Key.from_encoded_key(account["key"])
        if key.is_secret:
            raise ValueError(
                f"'{account['account_name']}' account's key is not a public key."
            )
        keys[key.public_key_hash()] = {
            "account_name": account["account_name"],
            "public_key": account["key"],
            "key_id": account["key_id"],
        }

logging.info(f"Writing keys to {config_path}/keys.json...")
with open(f"{config_path}/keys.json", "w") as keys_file:
    keys_json = json.dumps(keys, indent=2)
    print(keys_json, file=keys_file)
    logging.info(f"Wrote keys.")
    logging.debug(f"Keys: {keys_json}")
