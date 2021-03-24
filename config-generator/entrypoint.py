import argparse
import json
import os
import socket
from hashlib import blake2b
from json.decoder import JSONDecodeError
from operator import itemgetter
from pathlib import Path
from re import sub

from base58 import b58decode_check, b58encode_check
from nacl.signing import SigningKey

ACCOUNTS = json.loads(os.environ["ACCOUNTS"])
CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])
NODES = json.loads(os.environ["NODES"])

MY_POD_NAME = os.environ["MY_POD_NAME"]
MY_NODE_TYPE = MY_NODE = None
# The chain initiator job does not have a MY_NODE_TYPE or MY_NODE. Only
# statefulsets.
if os.environ.get("MY_NODE_TYPE"):
    MY_NODE_TYPE = os.environ["MY_NODE_TYPE"]
    MY_NODE = NODES[MY_NODE_TYPE][MY_POD_NAME]


BAKING_NODES = NODES["baking"]
NETWORK_CONFIG = CHAIN_PARAMS["network"]

SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA = CHAIN_PARAMS.get(
    "should_generate_unsafe_deterministic_data"
)

# If there are no genesis params, this is a public chain.
THIS_IS_A_PUBLIC_NET = True if not NETWORK_CONFIG.get("genesis") else False


def main():
    all_accounts = ACCOUNTS

    if SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA:
        fill_in_missing_genesis_block()
        all_accounts = fill_in_missing_baker_accounts()

    import_keys(all_accounts)

    if MY_POD_NAME in BAKING_NODES:
        # If this node is a baker, it must have an account with a secret key.
        verify_this_bakers_account(all_accounts)

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

    # Create parameters.json
    if main_args.generate_parameters_json:
        print("Starting parameters.json file generation")
        bootstrap_accounts_pubkey_hashes = get_bootstrap_accounts_pubkey_hashes(
            all_accounts
        )
        baker_bootstrap_accounts_pubkeys = get_bootstrap_baker_accounts_pubkeys(
            all_accounts
        )
        protocol_parameters = create_protocol_parameters_json(
            bootstrap_accounts_pubkey_hashes, baker_bootstrap_accounts_pubkeys
        )

        protocol_params_json = json.dumps(protocol_parameters, indent=2)
        with open("/etc/tezos/parameters.json", "w") as json_file:
            print(protocol_params_json, file=json_file)

    # Create config.json
    if main_args.generate_config_json:
        print("\nStarting config.json file generation")
        bootstrap_peers = CHAIN_PARAMS.get("bootstrap_peers", [])

        my_zerotier_ip = None
        zerotier_data_file_path = Path("/var/tezos/zerotier_data.json")
        if is_chain_running_on_zerotier_net(zerotier_data_file_path):
            my_zerotier_ip = get_my_pods_zerotier_ip(zerotier_data_file_path)
            if bootstrap_peers == []:
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())

        if THIS_IS_A_PUBLIC_NET:
            with open("/tmp/data/config.json", "r") as f:
                bootstrap_peers.extend(json.load(f)["p2p"]["bootstrap-peers"])
        else:
            local_bootstrap_peers = []
            for baker_name, baker_settings in BAKING_NODES.items():
                my_pod_fqdn_with_port = f"{socket.getfqdn()}:9732"
                if (
                    baker_settings.get("is_bootstrap_node", False)
                    and baker_name not in my_pod_fqdn_with_port
                ):
                    # Construct the FBN of the bootstrap node for all node's bootstrap_peers
                    bootstrap_peer_domain = sub(r"-\d+$", "", baker_name)
                    bootstrap_peer_fbn_with_port = (
                        f"{baker_name}.{bootstrap_peer_domain}:9732"
                    )
                    local_bootstrap_peers.append(bootstrap_peer_fbn_with_port)
            bootstrap_peers.extend(local_bootstrap_peers)

        if not bootstrap_peers and not MY_NODE.get("is_bootstrap_node", False):
            raise Exception(
                "ERROR: No bootstrap peers found for this non-bootstrap node"
            )

        config_json = json.dumps(
            create_node_config_json(
                bootstrap_peers,
                my_zerotier_ip,
            ),
            indent=2,
        )
        print("Generated config.json :")
        print(config_json)
        with open("/etc/tezos/config.json", "w") as json_file:
            print(config_json, file=json_file)


# If NETWORK_CONFIG["genesis"]["block"] hasn't been specified, we generate a
# deterministic one.
def fill_in_missing_genesis_block():
    print("\nEnsure that we have genesis_block")
    genesis_config = NETWORK_CONFIG["genesis"]
    genesis_block_placeholder = "YOUR_GENESIS_BLOCK_HASH_HERE"

    if (
        genesis_config.get("block", genesis_block_placeholder)
        == genesis_block_placeholder
    ):
        print("Deterministically generating missing genesis_block")
        seed = "foo"
        gbk = blake2b(seed.encode(), digest_size=32).digest()
        gbk_b58 = b58encode_check(b"\x01\x34" + gbk).decode("utf-8")
        genesis_config["block"] = gbk_b58


# Secret and public keys are matches and need be processed together. Neither key
# must be specified, as later code will fill in the details if they are not.
#
# We create any missing accounts that are refered to by a node at
# BAKING_NODES to ensure that all named accounts exist.
def fill_in_missing_baker_accounts():
    print("\nFilling in any missing baker accounts...")
    new_accounts = {}
    for baker_name, baker_values in BAKING_NODES.items():
        baker_account_name = baker_values.get("bake_using_account")

        if not baker_account_name or baker_account_name not in ACCOUNTS:
            new_baker_account_name = None
            if not baker_account_name:
                print(f"A new account named {baker_name} will be created")
                new_baker_account_name = baker_name
            else:
                print(
                    f"Specified account named {baker_account_name} is missing and will be created"
                )
                new_baker_account_name = baker_account_name

            new_accounts[new_baker_account_name] = {
                "bootstrap_balance": CHAIN_PARAMS["default_bootstrap_mutez"],
                "is_bootstrap_baker_account": True,
            }
            # Add to the baker the account name it will use to bake
            baker_values["bake_using_account"] = new_baker_account_name

    return {**new_accounts, **ACCOUNTS}


# Verify that the current baker has a baker account with secret key
def verify_this_bakers_account(accounts):
    account_using_to_bake = MY_NODE.get("bake_using_account")
    if not account_using_to_bake:
        raise Exception(f"ERROR: No account specified for baker {MY_POD_NAME}")

    account = accounts.get(account_using_to_bake)
    if not account:
        raise Exception(
            f"ERROR: No account named {account_using_to_bake} found for baker {MY_POD_NAME}"
        )

    if account.get("type") != "secret" or not account.get("key"):
        raise Exception(
            "ERROR: Either a secret key was not provided or the key type not specified"
            f", for account {account_using_to_bake} for baker {MY_POD_NAME}"
        )


#
# import_keys() creates three files in /var/tezos/client which specify
# the keys for each of the accounts: secret_keys, public_keys, and
# public_key_hashs.
#
# We iterate over fill_in_missing_baker_accounts() which ensures that we
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


def import_keys(all_accounts):
    print("\nImporting keys")
    tezdir = "/var/tezos/client"
    secret_keys = []
    public_keys = []
    public_key_hashs = []

    for account_name, account_values in all_accounts.items():
        print("\n  Importing keys for account: " + account_name)
        account_key_type = account_values.get("type")
        account_key = account_values.get("key")
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

        if SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA:
            if sk == None and pk == None:
                print(
                    f"    Deriving secret key for account {account_name} from genesis_block"
                )
                seed = account_name + ":" + NETWORK_CONFIG["genesis"]["block"]
                sk = blake2b(seed.encode(), digest_size=32).digest()

        # If we have a secret key, whether provided or was generated above.
        if sk:
            # Verify the pk is derived from sk, and derive it from the sk in the
            # case where the sk was generated.
            if not pk:
                print("    Deriving public key from secret key")
            tmp_pk = SigningKey(sk).verify_key.encode()
            if pk and pk != tmp_pk:
                raise Exception("ERROR: secret/public key mismatch for " + account_name)
            pk = tmp_pk
        # Since there is no sk or pk for this account, log a warning that this
        # account will not be imported.
        elif not pk:
            print(
                f"WARNING: No keys were provided for account {account_name}. Nothing to import"
            )
            continue

        # At this point there is a pubkey. Every node will import it.

        pkh = blake2b(pk, digest_size=20).digest()

        pk_b58 = b58encode_check(edpk + pk).decode("utf-8")
        pkh_b58 = b58encode_check(tz1 + pkh).decode("utf-8")

        sk_b58 = None
        if sk:
            print("    Appending secret key")
            sk_b58 = b58encode_check(edsk + sk).decode("utf-8")
            secret_keys.append({"name": account_name, "value": "unencrypted:" + sk_b58})

        if SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA and not account_values.get("key"):
            # If it is not a bootstrap baker
            # account, set the public key on the account.
            if pk_b58 and not account_values.get("is_bootstrap_baker_account"):
                account_values["key"] = pk_b58
                account_values["type"] = "public"
                # If it is a bootstrap baker
                # account, set the secret key on the account.
            elif sk_b58 and account_values.get("is_bootstrap_baker_account"):
                account_values["key"] = sk_b58
                account_values["type"] = "secret"

        print(f"    Appending public key: {pk_b58}")
        public_keys.append(
            {
                "name": account_name,
                "value": {"locator": "unencrypted:" + pk_b58, "key": pk_b58},
            }
        )

        print(f"  Appending public key hash: {pkh_b58}")
        public_key_hashs.append({"name": account_name, "value": pkh_b58})

        print(f"  Account key type: {account_values.get('type')}")
        print(
            f"  Account bootstrap balance: {account_values.get('bootstrap_balance')}"
        )
        print(
            f"  Is account a bootstrap baker: {account_values.get('is_bootstrap_baker_account', False)}"
        )

    print("\n  Writing " + tezdir + "/secret_keys")
    json.dump(secret_keys, open(tezdir + "/secret_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_keys")
    json.dump(public_keys, open(tezdir + "/public_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_key_hashs")
    json.dump(public_key_hashs, open(tezdir + "/public_key_hashs", "w"), indent=4)


def get_bootstrap_accounts(accounts, keys_list, is_getting_accounts_for_bakers):
    keys = {}
    for key in keys_list:
        key_name = key["name"]
        bootstrap_balance = accounts[key_name].get("bootstrap_balance", "0")
        # Don't add accounts with 0 tez to parameters.json
        if bootstrap_balance == "0":
            continue

        # If we are handling pubkeys for baker accounts
        if is_getting_accounts_for_bakers and accounts[key_name].get(
            "is_bootstrap_baker_account", False
        ):
            keys[key_name] = {
                "key": key["value"]["key"],
                "bootstrap_balance": bootstrap_balance,
            }
        elif (  # We are handling pubkey hashes for regular accounts
            not is_getting_accounts_for_bakers
            and not accounts[key_name].get("is_bootstrap_baker_account", True)
        ):
            keys[key_name] = {
                "key": key["value"],
                "bootstrap_balance": bootstrap_balance,
            }

    return keys


# Get baking account's pubkeys for parameters.json bootstrap_accounts
def get_bootstrap_baker_accounts_pubkeys(accounts):
    with open("/var/tezos/client/public_keys", "r") as f:
        pubkey_list = json.load(f)
    return get_bootstrap_accounts(
        accounts, pubkey_list, is_getting_accounts_for_bakers=True
    )


# Get non-baking account's pubkey hashes for parameters.json bootstrap_accounts
def get_bootstrap_accounts_pubkey_hashes(accounts):
    with open("/var/tezos/client/public_key_hashs", "r") as f:
        pubkey_hash_list = json.load(f)
    return get_bootstrap_accounts(
        accounts, pubkey_hash_list, is_getting_accounts_for_bakers=False
    )


def get_genesis_accounts_pubkey_and_balance(accounts):
    pubkey_and_balance_pairs = []

    for account_values in accounts.values():
        pubkey_and_balance_pairs.append(
            [account_values["key"], account_values["bootstrap_balance"]]
        )

    return pubkey_and_balance_pairs


#
# commitments and bootstrap_accounts are not part of
# `CHAIN_PARAMS["protocol_parameters"]`. The commitment size for Florence was
# too large to load from Helm to k8s. So we are mounting a file containing them.
# bootstrap accounts always needs massaging so they are passed as arguments.
def create_protocol_parameters_json(bootstrap_accounts, bootstrap_baker_accounts):
    """ Create the protocol's parameters.json file """

    accounts = {**bootstrap_accounts, **bootstrap_baker_accounts}
    pubkeys_with_balances = get_genesis_accounts_pubkey_and_balance(accounts)

    protocol_activation = CHAIN_PARAMS["protocol_activation"]
    protocol_params = protocol_activation["protocol_parameters"]
    protocol_params["bootstrap_accounts"] = pubkeys_with_balances

    print(json.dumps(protocol_params, indent=4))

    if protocol_activation.get("should_include_commitments"):
        try:
            with open("/commitment-params.json", "r") as f:
                try:
                    commitments = json.load(f)
                    protocol_params["commitments"] = commitments
                    print("Commitments added to parameters.json")
                except JSONDecodeError:
                    print("No JSON found in /commitment-params.json")
                    pass
        except OSError:
            print("No commitment-params.json found")

    return protocol_params


def is_chain_running_on_zerotier_net(file):
    return file.is_file()


def get_my_pods_zerotier_ip(zerotier_data_file_path):
    with open(zerotier_data_file_path, "r") as f:
        return json.load(f)[0]["assignedAddresses"][0].split("/")[0]


def get_zerotier_bootstrap_peer_ips():
    with open("/var/tezos/zerotier_network_members.json", "r") as f:
        network_members = json.load(f)
    return [
        n["config"]["ipAssignments"][0]
        for n in network_members
        if "ipAssignments" in n["config"]
        and n["name"] == f"{CHAIN_PARAMS['network']['chain_name']}_bootstrap"
    ]


def get_genesis_pubkey():
    with open("/var/tezos/client/public_keys", "r") as f:
        pubkeys = json.load(f)
        genesis_pubkey = None
        for _, pubkey in enumerate(pubkeys):
            if pubkey["name"] == NETWORK_CONFIG["activation_account_name"]:
                genesis_pubkey = pubkey["value"]["key"]
                break
        if not genesis_pubkey:
            raise Exception("ERROR: Couldn't find the genesis_pubkey")
        return genesis_pubkey


def create_node_config_json(
    bootstrap_peers,
    net_addr=None,
):
    """ Create the node's config.json file """

    node_config = {
        "data-dir": "/var/tezos/node/data",
        "rpc": {
            "listen-addrs": [f"{os.getenv('MY_POD_IP')}:8732", "127.0.0.1:8732"],
        },
        "p2p": {
            "bootstrap-peers": bootstrap_peers,
            "listen-addr": (net_addr + ":9732" if net_addr else "[::]:9732"),
        },
        "shell": MY_NODE.get("config", {}).get("shell", {}),
        # "log": {"level": "debug"},
    }

    if THIS_IS_A_PUBLIC_NET:
        node_config["network"] = NETWORK_CONFIG["chain_name"]
    else:
        if CHAIN_PARAMS.get("expected-proof-of-work") != None:
            node_config["p2p"]["expected-proof-of-work"] = CHAIN_PARAMS[
                "expected-proof-of-work"
            ]

        node_config["network"] = {
            "chain_name": NETWORK_CONFIG["chain_name"],
            "sandboxed_chain_name": "SANDBOXED_TEZOS",
            "default_bootstrap_peers": [],
            "genesis": NETWORK_CONFIG["genesis"],
            "genesis_parameters": {
                "values": {"genesis_pubkey": get_genesis_pubkey()},
            },
        }

    return node_config


if __name__ == "__main__":
    main()
