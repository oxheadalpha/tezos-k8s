import argparse
import collections
import json
import os
import re
import requests
import socket
import sys
from grp import getgrnam
from hashlib import blake2b
from pathlib import Path
from re import sub
from shutil import chown
from typing import Union

import requests
from base58 import b58encode_check
from pytezos import Key

with open("/etc/secret-volume/ACCOUNTS", "r") as secret_file:
    ACCOUNTS = json.loads(secret_file.read())
CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])
DATA_DIR = "/var/tezos/node/data"
NODE_GLOBALS = json.loads(os.environ["NODE_GLOBALS"]) or {}
NODES = json.loads(os.environ["NODES"])
NODE_IDENTITIES = json.loads(os.getenv("NODE_IDENTITIES", "{}"))
OCTEZ_SIGNERS = json.loads(os.getenv("OCTEZ_SIGNERS", "{}"))
OCTEZ_ROLLUP_NODES = json.loads(os.getenv("OCTEZ_ROLLUP_NODES", "{}"))
TACOINFRA_SIGNERS = json.loads(os.getenv("TACOINFRA_SIGNERS", "{}"))

MY_POD_NAME = os.environ["MY_POD_NAME"]
MY_POD_TYPE = os.environ["MY_POD_TYPE"]

MY_POD_CLASS = {}
MY_POD_CONFIG = {}
ALL_NODES = {}
BAKING_NODES = {}

for cl, val in NODES.items():
    if val != None:
        for i, inst in enumerate(val["instances"]):
            name = f"{cl}-{i}"
            ALL_NODES[name] = inst
            if name == MY_POD_NAME:
                MY_POD_CLASS = val
                MY_POD_CONFIG = inst
            if "runs" in val:
                if "baker" in val["runs"]:
                    BAKING_NODES[name] = inst

# MY_POD_CLASS is not set after iterating nodes configurations,
# this can happen when the pod is one which scaled out by autoscaler.
# Set this value to the value mapped by MY_NODE_CLASS to read possible config specified in at NODES
if not MY_POD_CLASS and "MY_NODE_CLASS" in os.environ:
    my_node_class = os.environ["MY_NODE_CLASS"]
    MY_POD_CLASS = NODES[my_node_class]

if MY_POD_TYPE == "signing":
    MY_POD_CONFIG = OCTEZ_SIGNERS[MY_POD_NAME]
if MY_POD_TYPE == "rollup":
    MY_POD_CONFIG = OCTEZ_ROLLUP_NODES[MY_POD_NAME]

NETWORK_CONFIG = CHAIN_PARAMS["network"]

# If there are no genesis params, we are dealing with a public network.
THIS_IS_A_PUBLIC_NET = True if not NETWORK_CONFIG.get("genesis") else False
# Even if we are dealing with a public network, we may not want to join it in a
# case such as when creating a network replica.
JOIN_PUBLIC_NETWORK = NETWORK_CONFIG.get("join_public_network", THIS_IS_A_PUBLIC_NET)
if not THIS_IS_A_PUBLIC_NET and JOIN_PUBLIC_NETWORK:
    raise ValueError(
        "Instruction was given to join a public network while defining a private chain"
    )


def main():
    all_accounts = ACCOUNTS

    import_keys(all_accounts)

    if MY_POD_NAME in BAKING_NODES:
        # If this node is a baker, it must have an account with a secret key.
        verify_this_bakers_account(all_accounts)

    # Create the node's identity.json if its values are provided
    if NODE_IDENTITIES.get(MY_POD_NAME, False):
        create_node_identity_json()

    # Create parameters.json
    if MY_POD_TYPE == "activating":
        print("Starting parameters.json file generation")
        protocol_parameters = create_protocol_parameters_json(all_accounts)

        protocol_params_json = json.dumps(protocol_parameters, indent=2)
        with open("/etc/tezos/parameters.json", "w") as json_file:
            print(protocol_params_json, file=json_file)

        with open("/etc/tezos/activation_account_name", "w") as file:
            print(NETWORK_CONFIG["activation_account_name"], file=file)

    # Create config.json
    if MY_POD_TYPE == "node":
        print("\nStarting config.json file generation")
        bootstrap_peers = CHAIN_PARAMS.get("bootstrap_peers", [])

        if JOIN_PUBLIC_NETWORK:
            with open("/etc/tezos/data/config.json", "r") as f:
                bootstrap_peers.extend(json.load(f)["p2p"]["bootstrap-peers"])
        else:
            local_bootstrap_peers = []
            for name, settings in ALL_NODES.items():
                print(" -- is " + name + " a bootstrap peer?\n")
                my_pod_fqdn_with_port = f"{socket.getfqdn()}:9732"
                if (
                    settings.get("is_bootstrap_node", False)
                    and name not in my_pod_fqdn_with_port
                ):
                    # Construct the FBN of the bootstrap node for all node's bootstrap_peers
                    print(" -- YES!\n")
                    bootstrap_peer_domain = sub(r"-\d+$", "", name)
                    bootstrap_peer_fbn_with_port = (
                        f"{name}.{bootstrap_peer_domain}:9732"
                    )
                    local_bootstrap_peers.append(bootstrap_peer_fbn_with_port)
            bootstrap_peers.extend(local_bootstrap_peers)

        if not bootstrap_peers and not MY_POD_CONFIG.get("is_bootstrap_node", False):
            raise Exception(
                "ERROR: No bootstrap peers found for this non-bootstrap node"
            )

        node_config = create_node_config_json(
            bootstrap_peers,
        )
        node_config_json = json.dumps(
            node_config,
            indent=2,
        )
        print("Generated config.json :")
        print(node_config_json)
        with open("/etc/tezos/config.json", "w") as json_file:
            print(node_config_json, file=json_file)

        if not os.path.isdir(f"{DATA_DIR}/context"):
            node_snapshot_config = create_node_snapshot_config_json(
                node_config["shell"]["history_mode"]
            )
            node_snapshot_config_json = json.dumps(
                node_snapshot_config,
                indent=2,
            )
            if node_snapshot_config:
                print("Generated snapshot_config.json :")
                print(node_snapshot_config_json)
                with open("/var/tezos/snapshot_config.json", "w") as json_file:
                    print(node_snapshot_config_json, file=json_file)


def verify_this_bakers_account(accounts):
    """
    Verify the current baker pod has an account with a secret key, unless the
    account is signed for via an external remote signer (e.g. Tacoinfra).
    """
    accts = MY_POD_CONFIG.get("bake_using_accounts")

    if not accts or len(accts) < 1:
        raise Exception("ERROR: No baker accounts specified")

    for acct in accts:
        if not accounts.get(acct):
            raise Exception(f"ERROR: No account named {acct} found.")
        signer_url = accounts[acct].get("signer_url")
        tacoinfra_signer = get_accounts_signer(TACOINFRA_SIGNERS, acct)

        # We can count on accounts[acct]["type"] because import_keys will
        # fill it in when it is missing.
        if not (accounts[acct]["type"] == "secret" or signer_url or tacoinfra_signer):
            raise Exception(
                f"ERROR: Neither a secret key, signer url, or cloud remote signer is provided for baking account{acct}."
            )

    return True


#
# import_keys() creates three files in /var/tezos/client which specify
# the keys for each of the accounts: secret_keys, public_keys, and
# public_key_hashs.
#
# If the account has a private key specified, we parse it and use it to
# derive the public key and its hash.  If a public key is also specified,
# we check to ensure that it matches the secret key.
#
# import_keys() also fills in "pk" and "pkh" as the public key and
# public key hash as a side-effect.  These are used later.


def expose_secret_key(account_name):
    """
    Decides if an account needs to have its secret key exposed on the current
    pod.  It returns the obvious Boolean.
    """
    if MY_POD_TYPE == "activating":
        all_authorized_keys = [
            key
            for node in NODES.values()
            for instance in node["instances"]
            for key in instance.get("authorized_keys", [])
        ]
        if account_name in all_authorized_keys:
            # Populate authorized keys known by all bakers in the activation account.
            # This ensures that activation will succeed with a remote signer that requires auth,
            # regardless of which baker does it.
            return True
        return NETWORK_CONFIG["activation_account_name"] == account_name

    if MY_POD_TYPE == "signing":
        return account_name in MY_POD_CONFIG.get("accounts")

    if MY_POD_TYPE == "rollup":
        return account_name == MY_POD_CONFIG.get("operator_account")

    if MY_POD_TYPE == "node":
        if account_name in MY_POD_CONFIG.get("authorized_keys", {}):
            return True
        return account_name in MY_POD_CONFIG.get("bake_using_accounts", {})

    return False


def get_accounts_signer(signers, account_name):
    """
    Determine if there is a signer for the account. Error if the account is
    specified in more than one signer.
    """
    found_signer = found_account = None
    for signer in signers.items():
        signer_name, signer_config = signer
        if account_name in signer_config["accounts"]:
            if account_name == found_account:
                raise Exception(
                    f"ERORR: Account '{account_name}' can't be specified in more than one signer."
                )
            found_account = account_name
            found_signer = {"name": signer_name, "config": signer_config}
    return found_signer


def get_remote_signer_url(account: tuple[str, dict], key: Key) -> Union[str, None]:
    """
    Return the url of a remote signer, if any, that claims to sign for the
    account. Error if more than one signs for the account.
    """
    account_name, account_values = account

    signer_url = account_values.get("signer_url")
    octez_signer = get_accounts_signer(OCTEZ_SIGNERS, account_name)
    tacoinfra_signer = get_accounts_signer(TACOINFRA_SIGNERS, account_name)

    signers = (signer_url, octez_signer, tacoinfra_signer)
    if tuple(map(bool, (signers))).count(True) > 1:
        raise Exception(
            f"ERROR: Account '{account_name}' may only have a signer_url field or be signed for by a single signer."
        )

    if octez_signer:
        signer_url = f"http://{octez_signer['name']}.octez-signer:6732"

    if tacoinfra_signer:
        signer_url = f"http://{tacoinfra_signer['name']}:5000"

    return signer_url and f"{signer_url}/{key.public_key_hash()}"


def get_secret_key(account, key: Key):
    """
    For nodes and activation job, check if there is a remote signer for the
    account. If found, use its url as the sk. If there is no signer and for all
    other pod types (e.g. octez signer), use an actual sk.
    """
    account_name, _ = account

    sk = (key.is_secret or None) and f"unencrypted:{key.secret_key()}"
    if MY_POD_TYPE in ("node", "activating"):
        signer_url = get_remote_signer_url(account, key)
        octez_signer = get_accounts_signer(OCTEZ_SIGNERS, account_name)
        if (sk and signer_url) and not octez_signer:
            raise Exception(
                f"ERROR: Account {account_name} can't have both a secret key and cloud signer."
            )
        elif signer_url:
            # Use signer for this account even if there's a sk
            sk = signer_url
            print(f"    Using remote signer url: {sk}")

    return sk


def import_keys(all_accounts):
    print("\nImporting keys")
    tezdir = "/var/tezos/client"
    secret_keys = []
    public_keys = []
    public_key_hashs = []
    authorized_keys = []

    for account_name, account_values in all_accounts.items():
        print("\n  Importing keys for account: " + account_name)
        account_key = account_values.get("key")

        if account_key == None:
            raise Exception(f"{account_name} defined w/o a key")

        key = Key.from_encoded_key(account_key)
        account_values["type"] = "secret" if key.is_secret else "public"

        # restrict which private key is exposed to which pod
        if expose_secret_key(account_name):
            sk = get_secret_key((account_name, account_values), key)
            if not sk:
                raise Exception("Secret key required but not provided.")
            print("    Appending secret key")
            secret_keys.append({"name": account_name, "value": sk})

        pk_b58 = key.public_key()
        print(f"    Appending public key: {pk_b58}")
        public_keys.append(
            {
                "name": account_name,
                "value": {"locator": "unencrypted:" + pk_b58, "key": pk_b58},
            }
        )
        account_values["pk"] = pk_b58

        pkh_b58 = key.public_key_hash()
        print(f"    Appending public key hash: {pkh_b58}")
        public_key_hashs.append({"name": account_name, "value": pkh_b58})
        account_values["pkh"] = pkh_b58

        if MY_POD_TYPE == "signing" and account_name in MY_POD_CONFIG.get(
            "authorized_keys", {}
        ):
            print(f"    Appending authorized key: {pk_b58}")
            authorized_keys.append({"name": account_name, "value": pk_b58})

        print(f"    Account key type: {account_values.get('type')}")
        print(
            f"    Account bootstrap balance: "
            + f"{account_values.get('bootstrap_balance')}"
        )
        print(
            f"    Is account a bootstrap baker: "
            + f"{account_values.get('is_bootstrap_baker_account', False)}"
        )

    sk_path, pk_path, pkh_path, ak_path = (
        f"{tezdir}/secret_keys",
        f"{tezdir}/public_keys",
        f"{tezdir}/public_key_hashs",
        f"{tezdir}/authorized_keys",
    )
    print(f"\n  Writing {sk_path}")
    json.dump(secret_keys, open(sk_path, "w"), indent=4)
    print(f"  Writing {pk_path}")
    json.dump(public_keys, open(pk_path, "w"), indent=4)
    print(f"  Writing {pkh_path}")
    json.dump(public_key_hashs, open(pkh_path, "w"), indent=4)
    if MY_POD_TYPE == "signing" and len(authorized_keys) > 0:
        print(f"  Writing {ak_path}")
        json.dump(authorized_keys, open(ak_path, "w"), indent=4)


def create_node_identity_json():
    identity_file_path = f"{DATA_DIR}/identity.json"

    # Manually create the data directory and identity.json, and give the
    # same dir/file permissions that tezos gives when it creates them.
    print("\nWriting identity.json file from the instance config")
    print(f"Node id: {NODE_IDENTITIES.get(MY_POD_NAME)['peer_id']}")

    os.makedirs(DATA_DIR, 0o700, exist_ok=True)
    with open(
        identity_file_path,
        "w",
        opener=lambda path, flags: os.open(path, flags, 0o644),
    ) as identity_file:
        print(json.dumps(NODE_IDENTITIES.get(MY_POD_NAME)), file=identity_file)

    nogroup = getgrnam("nogroup").gr_gid
    chown(DATA_DIR, user=1000, group=nogroup)
    chown(identity_file_path, user=1000, group=nogroup)
    print(f"Identity file written at {identity_file_path}")


#
# get_genesis_accounts_pubkey_and_balance(accounts) returns a list
# of lists: [ [key1, balance2], [key2, balance2], ... ] for all of
# the accounts prepopulated on our new chain.  Currently, if a public
# key is provided then the account is signed up as a baker from the
# start.  If just a public key hash is provided, then it is not.  We
# use a public key if the property "is_bootstrap_baker_account" is
# either absent or true.
def get_genesis_accounts_pubkey_and_balance(accounts):
    pubkey_and_balance_pairs = []

    for v in accounts.values():
        if "bootstrap_balance" in v and v["bootstrap_balance"] != "0":
            if not v.get("is_bootstrap_baker_account", True):
                key = v.get("pkh")
            else:
                key = v.get("pk")
            pubkey_and_balance_pairs.append([key, v["bootstrap_balance"]])

    return pubkey_and_balance_pairs


#
# bootstrap_contracts are not part of `CHAIN_PARAMS["protocol_parameters"]`.
# We are mounting a file containing them, since they are too large to be passed
# as helm parameters.
# bootstrap accounts always needs massaging so they are passed as arguments.
def create_protocol_parameters_json(accounts):
    """Create the protocol's parameters.json file"""

    pubkeys_with_balances = get_genesis_accounts_pubkey_and_balance(accounts)

    protocol_activation = CHAIN_PARAMS["protocol_activation"]
    protocol_params = protocol_activation["protocol_parameters"]
    protocol_params["bootstrap_accounts"] = pubkeys_with_balances

    print(json.dumps(protocol_activation, indent=4))

    # genesis contracts are downloaded from a http location (like a bucket)
    # they are typically too big to be passed directly to helm
    if protocol_activation.get("bootstrap_contract_urls"):
        protocol_params["bootstrap_contracts"] = []
        for url in protocol_activation["bootstrap_contract_urls"]:
            print(f"Injecting bootstrap contract from {url}")
            protocol_params["bootstrap_contracts"].append(requests.get(url).json())

    # Append any additional bootstrap params such as smart rollups, if any
    if protocol_activation.get("bootstrap_parameters"):
        protocol_params = {
            **protocol_params,
            **protocol_activation.get("bootstrap_parameters"),
        }

    return protocol_params


def get_genesis_pubkey():
    with open("/var/tezos/client/public_keys", "r") as f:
        pubkeys = json.load(f)
        genesis_pubkey = None
        for _, pubkey in enumerate(pubkeys):
            if pubkey["name"] == NETWORK_CONFIG["activation_account_name"]:
                genesis_pubkey = pubkey["value"]["key"]
                break
        if not genesis_pubkey:
            raise Exception(
                "ERROR: Couldn't find the genesis_pubkey. "
                + "This generally happens if you forgot to "
                + "define an account for the activation account"
            )
        return genesis_pubkey


def recursive_update(d, u):
    """
    Recursive dict update
    Used to merge node's config passed as chart values
    and computed values
    https://stackoverflow.com/a/3233356/207209
    """
    for k, v in u.items():
        if isinstance(v, collections.abc.Mapping):
            d[k] = recursive_update(d.get(k, {}), v)
        else:
            d[k] = v
    return d


def create_node_config_json(
    bootstrap_peers,
    net_addr=None,
):
    """Create the node's config.json file"""

    computed_node_config = {
        "data-dir": DATA_DIR,
        "rpc": {
            "listen-addrs": [f"{os.getenv('MY_POD_IP')}:8732", "127.0.0.1:8732"],
            "acl": [{"address": os.getenv("MY_POD_IP"), "blacklist": []}],
        },
        "p2p": {
            "bootstrap-peers": bootstrap_peers,
            "listen-addr": (net_addr + ":9732" if net_addr else "[::]:9732"),
        },
        # "log": {"level": "debug"},
    }
    node_config = NODE_GLOBALS.get("config", {})
    node_config = recursive_update(node_config, MY_POD_CLASS.get("config", {}))
    node_config = recursive_update(node_config, MY_POD_CONFIG.get("config", {}))
    node_config = recursive_update(node_config, computed_node_config)

    if THIS_IS_A_PUBLIC_NET:
        # `octez-node config --network ...` will have been run in config-init.sh
        #  producing a config.json. The value passed to the `--network` flag may
        #  have been the chain name or a url to the config.json of the chain.
        #  Either way, set the `network` field here as the `network` object of the
        #  produced config.json.
        with open("/etc/tezos/data/config.json", "r") as f:
            node_config_orig = json.load(f)
            if "network" in node_config_orig:
                node_config["network"] = node_config_orig["network"]
            else:
                node_config["network"] = "mainnet"

    else:
        if CHAIN_PARAMS.get("expected-proof-of-work") != None:
            node_config["p2p"]["expected-proof-of-work"] = CHAIN_PARAMS[
                "expected-proof-of-work"
            ]

        # Make a shallow copy of NETWORK_CONFIG so we can delete top level props
        # without mutating the original dict.
        node_config["network"] = dict(NETWORK_CONFIG)
        # Delete props that are not part of the node config.json spec
        node_config["network"].pop("activation_account_name")
        node_config["network"].pop("join_public_network", None)

        node_config["network"]["sandboxed_chain_name"] = "SANDBOXED_TEZOS"
        node_config["network"]["default_bootstrap_peers"] = []
        node_config["network"]["genesis_parameters"] = {
            "values": {"genesis_pubkey": get_genesis_pubkey()}
        }

    return node_config


def create_node_snapshot_config_json(history_mode):
    """Create this node's snapshot config"""

    if os.environ.get("SNAPSHOT_METADATA_NETWORK_NAME"):
        network_name = os.environ.get("SNAPSHOT_METADATA_NETWORK_NAME")
    else:
        network_name = NETWORK_CONFIG.get("chain_name")
    prefer_tarballs = os.environ.get("PREFER_TARBALLS", "").lower() in (
        "true",
        "1",
        "t",
    )
    artifact_type = "tarball" if prefer_tarballs else "tezos-snapshot"
    rolling_tarball_url = os.environ.get("ROLLING_TARBALL_URL")
    full_tarball_url = os.environ.get("FULL_TARBALL_URL")
    archive_tarball_url = os.environ.get("ARCHIVE_TARBALL_URL")
    rolling_snapshot_url = os.environ.get("ROLLING_SNAPSHOT_URL")
    full_snapshot_url = os.environ.get("FULL_SNAPSHOT_URL")
    if (
        rolling_tarball_url
        or full_tarball_url
        or rolling_snapshot_url
        or full_snapshot_url
        or archive_tarball_url
    ):
        print("Snapshot or tarball URL found, will ignore snapshot_source")
        match history_mode:
            case "rolling":
                if rolling_tarball_url:
                    return {"url": rolling_tarball_url, "artifact_type": "tarball"}
                elif rolling_snapshot_url:
                    return {
                        "url": rolling_snapshot_url,
                        "artifact_type": "tezos-snapshot",
                    }
                return
            case "full":
                if full_tarball_url:
                    return {"url": full_tarball_url, "artifact_type": "tarball"}
                elif full_snapshot_url:
                    return {"url": full_snapshot_url, "artifact_type": "tezos-snapshot"}
                return
            case "archive":
                if archive_tarball_url:
                    return {"url": archive_tarball_url, "artifact_type": "tarball"}
                return
            case _:
                print(f"Error: history mode {history_mode} is not known.")
                sys.exit(1)

    if "images" in MY_POD_CLASS and "octez" in MY_POD_CLASS["images"]:
        octez_container_version = MY_POD_CLASS["images"]["octez"]
    else:
        octez_container_version = os.environ.get("OCTEZ_VERSION")
    snapshot_source = os.environ.get("SNAPSHOT_SOURCE")
    if snapshot_source:
        try:
            response = requests.get(snapshot_source)
            response.raise_for_status()  # Raises an HTTPError if the HTTP request returned an unsuccessful status code
            all_snapshots = response.json()
        except (
            requests.exceptions.RequestException,
            requests.exceptions.JSONDecodeError,
        ):  # Catches exceptions related to requests and invalid JSON
            print(f"Error: unable to retrieve snapshot metadata from {snapshot_source}")
            return
    else:
        return
    try:
        octez_long_version = octez_container_version.split(":")[1]
        octez_version_re = re.search(r"v(\d+)", octez_long_version)
        octez_version = octez_version_re and octez_version_re.group(1)
    except Exception:
        octez_version = None

    print(
        f"""
Searching for snapshots from {snapshot_source}
with history mode {history_mode}
and artifact type {artifact_type}
and chain name {network_name}
and octez version {octez_version}.
    """
    )
    # find snapshot matching all the requested fields
    matching_snapshots = [
        s
        for s in all_snapshots.get("data", [])
        if s.get("history_mode") == history_mode
        and s.get("artifact_type") == artifact_type
        and s.get("chain_name") == network_name
    ]
    if octez_version:
        version_matching_snapshots = [
            s
            for s in matching_snapshots
            if int(octez_version) == s.get("tezos_version").get("version").get("major")
        ]
        if len(version_matching_snapshots):
            # If we can't find snapshots of the right octez version, we just pick the most recent available.
            matching_snapshots = version_matching_snapshots
    matching_snapshots = sorted(matching_snapshots, key=lambda s: s.get("block_height"))

    return matching_snapshots[-1] if len(matching_snapshots) else None


if __name__ == "__main__":
    main()
