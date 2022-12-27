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


from pytezos import pytezos
from base58 import b58encode_check

with open("/etc/secret-volume/ACCOUNTS", "r") as secret_file:
    ACCOUNTS = json.loads(secret_file.read())
CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])
DATA_DIR = "/var/tezos/node/data"
NODE_GLOBALS = json.loads(os.environ["NODE_GLOBALS"]) or {}
NODES = json.loads(os.environ["NODES"])
NODE_IDENTITIES = json.loads(os.getenv("NODE_IDENTITIES", "{}"))
SIGNERS = json.loads(os.environ["SIGNERS"])

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
    MY_POD_CONFIG = SIGNERS[MY_POD_NAME]

NETWORK_CONFIG = CHAIN_PARAMS["network"]

SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA = CHAIN_PARAMS.get(
    "should_generate_unsafe_deterministic_data"
)

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

    if not THIS_IS_A_PUBLIC_NET:
        fill_in_missing_genesis_block()

    if SHOULD_GENERATE_UNSAFE_DETERMINISTIC_DATA:
        all_accounts = fill_in_missing_accounts()
        fill_in_missing_keys(all_accounts)

    fill_in_activation_account(all_accounts)
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

        my_zerotier_ip = None
        zerotier_data_file_path = Path("/var/tezos/zerotier_data.json")
        if is_chain_running_on_zerotier_net(zerotier_data_file_path):
            my_zerotier_ip = get_my_pods_zerotier_ip(zerotier_data_file_path)
            if bootstrap_peers == []:
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())

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
            my_zerotier_ip,
        )
        node_config_json = json.dumps(
            node_config,
            indent=2,
        )
        node_snapshot_config = create_node_snapshot_config_json(
            node_config["shell"]["history_mode"]
        )
        node_snapshot_config_json = json.dumps(
            node_snapshot_config,
            indent=2,
        )
        print("Generated config.json :")
        print(node_config_json)
        print("Generated snapshot_config.json :")
        print(node_snapshot_config_json)
        with open("/etc/tezos/config.json", "w") as json_file:
            print(node_config_json, file=json_file)
        with open("/var/tezos/snapshot_config.json", "w") as json_file:
            print(node_snapshot_config_json, file=json_file)


# If NETWORK_CONFIG["genesis"]["block"] hasn't been specified, we generate a
# deterministic one.
def fill_in_missing_genesis_block():
    genesis_config = NETWORK_CONFIG["genesis"]
    if not genesis_config.get("block"):
        print("Deterministically generating missing genesis_block")
        if not NETWORK_CONFIG.get("chain_name"):
            raise Exception("Genesis config is missing 'chain_name'.")
        seed = NETWORK_CONFIG["chain_name"]
        gbk = blake2b(seed.encode(), digest_size=32).digest()
        gbk_b58 = b58encode_check(b"\x01\x34" + gbk).decode("utf-8")
        genesis_config["block"] = gbk_b58


def fill_in_activation_account(accts):
    if "activation_account_name" not in NETWORK_CONFIG:
        print("Activation account missing:")
        for name, val in accts.items():
            if val.get("is_bootstrap_baker_account", False):
                print(f"    Setting activation account to {name}")
                NETWORK_CONFIG["activation_account_name"] = name
                return
        print("    failed to find one")


def get_baking_accounts(baker_values):
    acct = baker_values.get("bake_using_account")
    accts = baker_values.get("bake_using_accounts")

    if acct and accts:
        raise ValueError(
            'Mustn\'t specify both "bake_using_account" and "bake_using_accounts"'
        )

    if acct:
        accts = [acct]

    return accts


# Secret and public keys are matches and need be processed together. Neither key
# must be specified, as later code will fill in the details if they are not.
#
# We create any missing accounts that are referred to by a node at
# BAKING_NODES to ensure that all named accounts exist.
def fill_in_missing_accounts():
    print("\nFilling in any missing accounts...")
    new_accounts = {}
    init_balance = CHAIN_PARAMS["default_bootstrap_mutez"]
    for baker_name, baker_values in BAKING_NODES.items():
        accts = get_baking_accounts(baker_values)

        if not accts:
            print(f"Defaulting to baking with account: {baker_name}")
            accts = [baker_name]

        baker_values["bake_using_account"] = None
        baker_values["bake_using_accounts"] = accts

        for acct in accts:
            if acct not in ACCOUNTS:
                print(f"Creating account: {acct}")
                new_accounts[acct] = {
                    "bootstrap_balance": init_balance,
                    "is_bootstrap_baker_account": True,
                }

    try:
        acct = NETWORK_CONFIG["activation_account_name"]
        if acct not in ACCOUNTS and acct not in new_accounts:
            print(f"Creating activation account: {acct}")
            new_accounts[acct] = {
                "bootstrap_balance": CHAIN_PARAMS["default_bootstrap_mutez"],
            }
    except:
        pass

    return {**new_accounts, **ACCOUNTS}


# Verify that the current baker has a baker account with secret key
def verify_this_bakers_account(accounts):
    accts = get_baking_accounts(MY_POD_CONFIG)

    if not accts or len(accts) < 1:
        raise Exception("ERROR: No baker accounts specified")

    for acct in accts:
        if not accounts.get(acct):
            raise Exception(f"ERROR: No account named {acct} found.")
        signer = accounts[acct].get("signer_url")

        # We can count on accounts[acct]["type"] because import_keys will
        # fill it in when it is missing.
        if not (accounts[acct]["type"] == "secret" or signer):
            raise Exception(
                f"ERROR: Either a secret key or a signer_url should be provided for {acct}"
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
#
# import_keys() also fills in "pk" and "pkh" as the public key and
# public key hash as a side-effect.  These are used later.

edsk = b"\x0d\x0f\x3a\x07"


def fill_in_missing_keys(all_accounts):
    print("\nFill in missing keys")

    for account_name, account_values in all_accounts.items():
        if "type" in account_values:
            raise Exception(
                "Deprecated field 'type' passed by helm, but helm should have pruned it."
            )
        account_key = account_values.get("key")

        if account_key == None:
            print(
                f"  Deriving secret key for account "
                + f"{account_name} from genesis_block"
            )
            seed = account_name + ":" + NETWORK_CONFIG["genesis"]["block"]
            sk = blake2b(seed.encode(), digest_size=32).digest()
            sk_b58 = b58encode_check(edsk + sk).decode("utf-8")
            account_values["key"] = sk_b58
            account_values["type"] = "secret"


#
# expose_secret_key() decides if an account needs to have its secret
# key exposed on the current pod.  It returns the obvious Boolean.


def expose_secret_key(account_name):
    if MY_POD_TYPE == "activating":
        return NETWORK_CONFIG["activation_account_name"] == account_name

    if MY_POD_TYPE == "signing":
        return account_name in MY_POD_CONFIG.get("sign_for_accounts")

    if MY_POD_TYPE == "node":
        if MY_POD_CONFIG.get("bake_using_account", "") == account_name:
            return True
        return account_name in MY_POD_CONFIG.get("bake_using_accounts", {})

    return False


#
# pod_requires_secret_key() decides if a pod requires the secret key,
# regardless of a remote_signer being present.  E.g. the remote signer
# needs to have the keys not a URL to itself.


def pod_requires_secret_key(account_values):
    return (
        MY_POD_TYPE in ["activating", "signing"] and "signer_url" not in account_values
    )


#
# remote_signer() returns a reference to a signer that
# tezos-client understands, either:
# * picks the first signer, if any, that claims to sign
#   for account_name and returns a URL to locate it,
# * returns the external signer url if passed.


def remote_signer(account_name, external_signer_url, key):
    signer_url_no_path = None
    if external_signer_url:
        signer_url_no_path = external_signer_url
    for k, v in SIGNERS.items():
        if account_name in v["sign_for_accounts"]:
            signer_url_no_path = f"http://{k}.tezos-signer:6732"
    if signer_url_no_path:
        return f"{signer_url_no_path}/{key.public_key_hash()}"
    return None


def import_keys(all_accounts):
    print("\nImporting keys")
    tezdir = "/var/tezos/client"
    secret_keys = []
    public_keys = []
    public_key_hashs = []

    for account_name, account_values in all_accounts.items():
        print("\n  Importing keys for account: " + account_name)
        account_key = account_values.get("key")

        if account_key == None:
            raise Exception(f"{account_name} defined w/o a key")

        key = pytezos.key.from_encoded_key(account_key)
        try:
            key.secret_key()
        except ValueError:
            account_values["type"] = "public"
        else:
            account_values["type"] = "secret"

        # restrict which private key is exposed to which pod
        if expose_secret_key(account_name):
            signer = account_values.get("signer_url")
            if signer:
                print("\n  Using signer outside of chart: " + signer)
            sk = remote_signer(account_name, signer, key)
            if sk == None or pod_requires_secret_key(account_values):
                try:
                    sk = "unencrypted:" + key.secret_key()
                except ValueError:
                    raise ("Secret key required but not provided.")

                print("    Appending secret key")
            else:
                print("    Using remote signer: " + sk)
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
        print(f"  Appending public key hash: {pkh_b58}")
        public_key_hashs.append({"name": account_name, "value": pkh_b58})
        account_values["pkh"] = pkh_b58

        # XXXrcd: fix this print!

        print(f"  Account key type: {account_values.get('type')}")
        print(
            f"  Account bootstrap balance: "
            + f"{account_values.get('bootstrap_balance')}"
        )
        print(
            f"  Is account a bootstrap baker: "
            + f"{account_values.get('is_bootstrap_baker_account', False)}"
        )

    print("\n  Writing " + tezdir + "/secret_keys")
    json.dump(secret_keys, open(tezdir + "/secret_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_keys")
    json.dump(public_keys, open(tezdir + "/public_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_key_hashs")
    json.dump(public_key_hashs, open(tezdir + "/public_key_hashs", "w"), indent=4)


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

    network_name = NETWORK_CONFIG.get("chain_name")
    prefer_tarballs = os.environ["PREFER_TARBALLS"].lower() in ('true', '1', 't')
    artifact_type = "tarball" if prefer_tarballs else "tezos-snapshot"
    rolling_tarball_url = os.environ["ROLLING_TARBALL_URL"]
    full_tarball_url = os.environ["FULL_TARBALL_URL"]
    archive_tarball_url = os.environ["ARCHIVE_TARBALL_URL"]
    rolling_snapshot_url = os.environ["ROLLING_SNAPSHOT_URL"]
    full_snapshot_url = os.environ["FULL_SNAPSHOT_URL"]
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

    octez_container_version = os.environ["OCTEZ_VERSION"]
    snapshot_source = os.environ["SNAPSHOT_SOURCE"]
    if snapshot_source:
        try:
            all_snapshots = requests.get(snapshot_source).json()
        except Exception as e:
            print(f"Error while fetching {snapshot_source}: {e}")
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
    try:
        matching_snapshots = [
            s
            for s in all_snapshots
            if s["history_mode"] == history_mode
            and s["artifact_type"] == artifact_type
            and s["chain_name"] == network_name
        ]
        if octez_version:
            matching_snapshots = [ s for s in matching_snapshots if  octez_version in s["tezos_version"] ]
        matching_snapshots = sorted(matching_snapshots, key=lambda d: d["block_height"])

        matching_snapshot = matching_snapshots[-1]
        return matching_snapshot
    except Exception:
        return None


if __name__ == "__main__":
    main()
