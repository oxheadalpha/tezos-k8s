import argparse
import json
import os
import socket
from hashlib import blake2b
from json.decoder import JSONDecodeError
from operator import itemgetter
from re import match

from base58 import b58decode_check, b58encode_check
from nacl.signing import SigningKey

CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])
ACCOUNTS = json.loads(os.environ["ACCOUNTS"])
MY_POD_NAME = os.environ("MY_POD_NAME")


def main():
    fill_in_missing_genesis_block()
    get_missing_baker_accounts()
    import_keys()

    print("Starting tezos config file generation")
    main_parser = argparse.ArgumentParser()
    main_parser.add_argument(
        "--generate-parameters-json",
        action="store_true",
        help="generate parameters.json",
    )
    main_parser.add_argument(
        "--generate-config-json", action="store_true", help="generate config.json"
    )
    main_args = main_parser.parse_args()

    bootstrap_baker_accounts = get_bootstrap_bakers_pubkeys(flattened_accounts)

    if main_args.generate_parameters_json:
        bootstrap_accounts = get_bootstrap_accounts_pubkey_hashes(flattened_accounts)
        protocol_parameters = create_protocol_parameters_json(
            bootstrap_accounts, bootstrap_baker_accounts
        )

        print("Generated parameters.json :")
        protocol_params_json = json.dumps(protocol_parameters, indent=2)
        print(protocol_params_json)
        with open("/etc/tezos/parameters.json", "w") as json_file:
            print(protocol_params_json, file=json_file)

    if main_args.generate_config_json:
        net_addr = None
        bootstrap_peers = CHAIN_PARAMS.get("bootstrap_peers", [])
        if CHAIN_PARAMS["chain_type"] == "private":
            with open("/var/tezos/zerotier_data.json", "r") as f:
                net_addr = json.load(f)[0]["assignedAddresses"][0].split("/")[0]
            if bootstrap_peers == []:
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())
        if CHAIN_PARAMS["chain_type"] == "public":
            with open("/tmp/data/config.json", "r") as f:
                bootstrap_peers.extend(json.load(f)["p2p"]["bootstrap-peers"])
        else:
            local_bootstrap_peers = []
            bakers = CHAIN_PARAMS["nodes"]["baking"]
            for i, node in enumerate(bakers):
                if (
                    node.get("bootstrap", False)
                    and f"tezos-baking-node-{i}" not in socket.gethostname()
                ):
                    local_bootstrap_peers.append(
                        f"tezos-baking-node-{i}.tezos-baking-node:9732"
                    )
            bootstrap_peers.extend(local_bootstrap_peers)
            if not bootstrap_peers:
                bootstrap_peers = [f"tezos-baking-node-0.tezos-baking-node:9732"]

        config_json = json.dumps(
            create_node_config_json(
                bootstrap_baker_accounts,
                bootstrap_peers,
                net_addr,
            ),
            indent=2,
        )
        print("Generated config.json :")
        print(config_json)
        with open("/etc/tezos/config.json", "w") as json_file:
            print(config_json, file=json_file)


def get_zerotier_bootstrap_peer_ips():
    with open("/var/tezos/zerotier_network_members.json", "r") as f:
        network_members = json.load(f)
    return [
        n["config"]["ipAssignments"][0]
        for n in network_members
        if "ipAssignments" in n["config"]
        and n["name"] == f"{CHAIN_PARAMS['chain_name']}_bootstrap"
    ]


def get_keys_and_balances(accounts, keys_list, for_bootstrap_bakers):
    keys = {}
    for key in keys_list:
        key_name = key["name"]
        if for_bootstrap_bakers and accounts[key_name]["is_bootstrap_baker_account"]:
            keys[key_name] = {
                "key": key["value"]["key"],
                "bootstrap_balance": accounts[key_name]["bootstrap_balance"],
            }
        elif (
            not for_bootstrap_bakers
            and not accounts[key_name]["is_bootstrap_baker_account"]
        ):
            keys[key_name] = {
                "key": key["value"],
                "bootstrap_balance": accounts[key_name]["bootstrap_balance"],
            }

    return keys


def get_bootstrap_bakers_pubkeys(accounts):
    with open("/var/tezos/client/public_keys", "r") as f:
        pubkey_list = json.load(f)
    return get_keys_and_balances(accounts, pubkey_list, for_bootstrap_bakers=True)


def get_bootstrap_accounts_pubkey_hashes(accounts):
    with open("/var/tezos/client/public_key_hashs", "r") as f:
        pubkey_hash_list = json.load(f)
    return get_keys_and_balances(accounts, pubkey_hash_list, for_bootstrap_bakers=False)


def get_this_nodes_settings():
    my_pod_name = os.getenv("MY_POD_NAME")

    if match("tezos-baking-node-\d", my_pod_name):
        baking_nodes = CHAIN_PARAMS["nodes"]["baking"]
        for node in baking_nodes:
            if node["name"] == my_pod_name:
                return node
    elif match("tezos-node-\d", my_pod_name):
        regular_nodes = CHAIN_PARAMS["nodes"]["regular"]
        for node in regular_nodes:
            if node["name"] == my_pod_name:
                return node

    print("Could not find any node setting for this node!")


def create_node_config_json(
    bootstrap_baker_accounts,
    bootstrap_peers,
    net_addr=None,
):
    """ Create the node's config.json file """

    this_nodes_settings = get_this_nodes_settings()

    node_config = {
        "data-dir": "/var/tezos/node/data",
        "rpc": {
            "listen-addrs": [f"{os.getenv('MY_POD_IP')}:8732", "127.0.0.1:8732"],
        },
        "p2p": {
            "bootstrap-peers": bootstrap_peers,
            "listen-addr": (net_addr + ":9732" if net_addr else "[::]:9732"),
        },
        "shell": {"history_mode": this_nodes_settings.get("history_mode", "rolling")}
        # "log": { "level": "debug"},
    }
    if CHAIN_PARAMS["chain_type"] == "public":
        node_config["network"] = CHAIN_PARAMS["network"]
    else:
        node_config["p2p"]["expected-proof-of-work"] = 0
        node_config["network"] = {
            "chain_name": CHAIN_PARAMS["chain_name"],
            "sandboxed_chain_name": "SANDBOXED_TEZOS",
            "default_bootstrap_peers": [],
            "genesis": {
                "timestamp": CHAIN_PARAMS["timestamp"],
                "block": CHAIN_PARAMS["genesis_block"],
                "protocol": "PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex",
            },
            "genesis_parameters": {
                "values": {
                    "genesis_pubkey": bootstrap_baker_accounts[
                        CHAIN_PARAMS["activation_account"]
                    ]["key"],
                },
            },
        }

    return node_config


def get_genesis_accounts_pubkey_and_balance(accounts, accounts_type):
    """ accounts_type = "plain_account" | "baker_account" """

    pubkey_and_balance_pairs = []

    for account in accounts:
        account_balance = str(account.get("bootstrap_balance"))

        # Don't add accounts with 0 tez to parameters.json
        if account_balance == "0":
            continue
        if (  # plain accounts || baker accounts but old account format
            accounts_type == "plain_accounts"
            or CHAIN_PARAMS["is_old_accounts_parameter_format"]
        ):
            pubkey_and_balance_pairs.append([account["key"], account_balance])
        else:  # baker accounts
            pubkey_and_balance_pairs.append(
                {"amount": account_balance, "key": account["key"]}
            )

    return pubkey_and_balance_pairs


#
# commitments and bootstrap_accounts are not part of
# `CHAIN_PARAMS["protocol_parameters"]`. The commitment size for Florence was
# too large to load from Helm to k8s. So we are mounting a file containing them.
# bootstrap accounts always needs massaging so they are passed as arguments.
def create_protocol_parameters_json(bootstrap_accounts, bootstrap_baker_accounts):
    """ Create the protocol's parameters.json file """

    protocol_params = CHAIN_PARAMS["protocol_parameters"]

    bootstrap_accounts_pubkey_balance_pairs = get_genesis_accounts_pubkey_and_balance(
        bootstrap_accounts.values(), "plain_accounts"
    )
    bootstrap_bakers_pubkey_balance_pairs = get_genesis_accounts_pubkey_and_balance(
        bootstrap_baker_accounts.values(), "baker_accounts"
    )

    if CHAIN_PARAMS["is_old_accounts_parameter_format"]:
        protocol_params["bootstrap_accounts"] = [
            *bootstrap_accounts_pubkey_balance_pairs,
            *bootstrap_bakers_pubkey_balance_pairs,
        ]
    else:
        protocol_params["bootstrap_accounts"] = bootstrap_accounts_pubkey_balance_pairs
        protocol_params["bootstrap_bakers"] = bootstrap_bakers_pubkey_balance_pairs

    with open("/commitment-params.json", "r") as f:
        try:
            commitments = json.load(f)
            protocol_params["commitments"] = commitments
        except JSONDecodeError:
            print("No JSON found in /commitment-params.json")
            pass

    return protocol_params


#
# If CHAIN_PARAMS["node_config_network"]["genesis"]["block"] hasn't been
# specified, we generate a deterministic one.


def fill_in_missing_genesis_block():
    print("Ensure that we have genesis_block")
    if CHAIN_PARAMS["node_config_network"]["genesis"]["block"] == "YOUR_GENESIS_BLOCK_HASH_HERE":
        print("  Generating missing genesis_block")
        seed = "foo"
        gbk = blake2b(seed.encode(), digest_size=32).digest()
        gbk_b58 = b58encode_check(b"\x01\x34" + gbk).decode("utf-8")
        CHAIN_PARAMS["genesis_block"] = gbk_b58


#
#
# Secret and public keys are matches and need be processed together. Neither key
# must be specified, as later code will fill in the details if they are not.
#
# We create any missing accounts that are refered to by by a node at
# CHAIN_PARAMS["nodes"]["baking"] to ensure that all named accounts exist.
#


def get_missing_baker_accounts():
    new_accounts = {}
    for baker_name, baker_values in CHAIN_PARAMS["nodes"]["baking"].items():
        baker_account_name = baker_values.get("bake_using_account")

        if not baker_account_name or baker_account_name not in ACCOUNTS:
            new_baker_account_name = None
            if not baker_account_name:
                print(
                    f"    A new account named {baker_name} will be created for this node "
                )
                new_baker_account_name = baker_name
            else:
                print(
                    f"    Specified account named {baker_account_name} is missing and will be created for this node "
                )
                new_baker_account_name = baker_account_name

            new_accounts[new_baker_account_name] = {
                "bootstrap_balance": CHAIN_PARAMS["defualt_bootstrap_mutez"],
                "is_bootstrap_baker_account": True,
            }

    return {**new_accounts, **ACCOUNTS}


#
# import_keys() creates three files in /var/tezos/client which specify
# the keys for each of the accounts: secret_keys, public_keys, and
# public_key_hashs.
#
# We iterate over get_missing_baker_accounts() which ensures that we
# have a full set of accounts for which to write keys.
#
# If the account has a private key specified, we parse it and use it to
# derive the public key and its hash.  If a public key is also specified,
# we check to ensure that it matches the secret key.  If neither a secret
# nor a public key are specified, then we derive one from a hash of
# the account name and the gensis_block (which may be generated above.)
#
# Both specified and generated keys are stable for the same _values.yaml
# files.  The specified keys for obvious reasons.  The generated keys
# are stable because we take care not to use any information that is not
# specified in the _values.yaml file in the seed used to generate them.

edsk = b"\x0d\x0f\x3a\x07"
edpk = b"\x0d\x0f\x25\xd9"
tz1 = b"\x06\xa1\x9f"


def import_keys():
    print("Importing keys")
    tezdir = "/var/tezos/client"
    secret_keys = []
    public_keys = []
    public_key_hashs = []
    for account_name, account_values in get_missing_baker_accounts().values():
        print("  Importing account: " + account_name)
        account_key_type = account_values["type"]
        account_key = account_values["key"]
        sk = pk = None

        # If a key is specified in the account
        if account_key_type == "secret":
            print("    Secret key specified")
            sk = b58decode_check(account_key)
            if sk[0:4] != edsk:
                print("WARNING: unrecognised secret key prefix")
            sk = sk[4:]
        if account_key_type == "public":
            print("    Public key specified")
            pk = b58decode_check(account_key)
            if pk[0:4] != edpk:
                print("WARNING: unrecognised public key prefix")
            pk = pk[4:]

        # If both a secret and public key are missing for this account, generate
        # a deterministic secret key
        if sk == None and pk == None:
            print(
                f"    Deriving secret key for account {account_name} from genesis_block"
            )
            seed = account_name + ":" + CHAIN_PARAMS["genesis_block"]
            sk = blake2b(seed.encode(), digest_size=32).digest()

        # If we have a secret key, whether provided or was generated above
        if sk != None:
            # Verify the public key is derived from the secret key
            if pk == None:
                print("    Deriving public key from secret key")
            tmp_pk = SigningKey(sk).verify_key.encode()
            if pk != None and pk != tmp_pk:
                print("ERROR: secret/public key mismatch for " + account_name)
                exit(1)
            pk = tmp_pk
        # If there is no secret key but there is a public key, and this account
        # is a bootstrap baker account, error as the baker needs a secret key
        elif pk != None and account_values["is_bootstrap_baker_account"]:
            print(f"ERROR: A secret key is required for a baker")
            exit(1)

        pkh = blake2b(pk, digest_size=20).digest()

        pk_b58 = b58encode_check(edpk + pk).decode("utf-8")
        pkh_b58 = b58encode_check(tz1 + pkh).decode("utf-8")

        if sk != None:
            print("    Appending secret key")
            sk_b58 = b58encode_check(edsk + sk).decode("utf-8")
            secret_keys.append({"name": account_name, "value": "unencrypted:" + sk_b58})

        print("    Appending public key")
        public_keys.append(
            {
                "name": account_name,
                "value": {"locator": "unencrypted:" + pk_b58, "key": pk_b58},
            }
        )

        print("    Appending public key hash")
        public_key_hashs.append({"name": account_name, "value": pkh_b58})

    print("  Writing " + tezdir + "/secret_keys")
    json.dump(secret_keys, open(tezdir + "/secret_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_keys")
    json.dump(public_keys, open(tezdir + "/public_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_key_hashs")
    json.dump(public_key_hashs, open(tezdir + "/public_key_hashs", "w"), indent=4)


if __name__ == "__main__":
    main()
