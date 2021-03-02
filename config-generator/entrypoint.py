import argparse
import json
import os
import socket
from hashlib import blake2b
from json.decoder import JSONDecodeError
from operator import itemgetter

from base58 import b58decode_check, b58encode_check
from nacl.signing import SigningKey

CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])
ACCOUNTS = json.loads(os.environ["ACCOUNTS"])


def main():
    fill_in_missing_genesis_block()
    flattened_accounts = flatten_accounts()
    import_keys(flattened_accounts)

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

    baker_public_keys = get_baker_public_keys(flattened_accounts)
    non_baker_public_key_hashes = get_non_baker_public_key_hashes(flattened_accounts)
    bootstrap_accounts = {**baker_public_keys, **non_baker_public_key_hashes}

    if main_args.generate_parameters_json:
        protocol_parameters = get_parameters_config([*bootstrap_accounts.values()])

        with open("/commitment-params.json", "r") as f:
            try:
                commitments = json.load(f)
                protocol_parameters["commitments"] = commitments
            except JSONDecodeError:
                print("No JSON found in /commitment-params.json")
                pass

        print("Generated parameters.json :")
        protocol_params_json = json.dumps(protocol_parameters, indent=2)
        print(protocol_params_json)
        with open("/etc/tezos/parameters.json", "w") as json_file:
            print(protocol_params_json, file=json_file)

    if main_args.generate_config_json:
        net_addr = None
        bootstrap_peers = CHAIN_PARAMS.get("bootstrap_peers", [])
        if CHAIN_PARAMS["zerotier_in_use"]:
            with open("/var/tezos/zerotier_data.json", "r") as f:
                net_addr = json.load(f)[0]["assignedAddresses"][0].split("/")[0]
            if bootstrap_peers == []:
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())
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
            get_node_config(
                CHAIN_PARAMS["chain_name"],
                baker_public_keys[CHAIN_PARAMS["activation_account"]]["key"],
                CHAIN_PARAMS["timestamp"],
                bootstrap_peers,
                CHAIN_PARAMS["genesis_block"],
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


def get_baker_public_keys(accounts):
    with open("/var/tezos/client/public_keys", "r") as f:
        tezos_pubkey_list = json.load(f)
    pubkeys = {}
    for key in tezos_pubkey_list:
        key_name = key["name"]
        if accounts[key_name]["bootstrap_baker"]:
            pubkeys[key_name] = {
                "key": key["value"]["key"],
                "balance": accounts[key_name]["balance"],
            }
    return pubkeys


def get_non_baker_public_key_hashes(accounts):
    with open("/var/tezos/client/public_key_hashs", "r") as f:
        pubkey_hash_list = json.load(f)
    hashes = {}
    for account in pubkey_hash_list:
        account_name = account["name"]
        if not accounts[account_name]["bootstrap_baker"]:
            hashes[account_name] = {
                "key": account["value"],
                "balance": accounts[account_name]["balance"],
            }
    return hashes


def get_node_config(
    chain_name,
    genesis_key,
    timestamp,
    bootstrap_peers,
    genesis_block=None,
    net_addr=None,
):
    p2p = ["p2p"]
    for bootstrap_peer in bootstrap_peers:
        p2p.extend(["--bootstrap-peers", bootstrap_peer])
    if net_addr:
        p2p.extend(["--listen-addr", net_addr + ":9732"])

    node_config_args = p2p + [
        "global",
        "rpc",
        "network",
        "--chain-name",
        chain_name,
        "genesis",
        "--timestamp",
        timestamp,
        "--block",
        genesis_block,
        "genesis_parameters",
        "--genesis-pubkey",
        genesis_key,
    ]

    return generate_node_config(node_config_args)


# FIXME - this should probably be replaced with subprocess calls to tezos-node-config
def generate_node_config(node_argv):
    parser = argparse.ArgumentParser(prog="nodeconfig")
    subparsers = parser.add_subparsers(help="sub-command help", dest="subparser_name")

    global_parser = subparsers.add_parser("global")
    global_parser.add_argument("--data-dir", default="/var/tezos/node")

    rpc_parser = subparsers.add_parser("rpc")
    rpc_parser.add_argument(
        "--listen-addrs",
        action="append",
        default=[f"{os.getenv('MY_POD_IP')}:8732", "127.0.0.1:8732"],
    )

    p2p_parser = subparsers.add_parser("p2p")
    p2p_parser.add_argument("--bootstrap-peers", action="append", default=[])
    p2p_parser.add_argument("--listen-addr", default="[::]:9732")
    p2p_parser.add_argument("--expected-proof-of-work", default=0, type=int)

    network_parser = subparsers.add_parser("network")
    network_parser.add_argument("--chain-name")
    network_parser.add_argument("--sandboxed-chain-name", default="SANDBOXED_TEZOS")
    network_parser.add_argument(
        "--default-bootstrap-peers", action="append", default=[]
    )

    genesis_parser = subparsers.add_parser("genesis")
    genesis_parser.add_argument("--timestamp")
    genesis_parser.add_argument(
        "--block", default="BLockGenesisGenesisGenesisGenesisGenesisd6f5afWyME7"
    )
    genesis_parser.add_argument(
        "--protocol", default="PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex"
    )

    genesis_parameters_parser = subparsers.add_parser("genesis_parameters")
    genesis_parameters_parser.add_argument("--genesis-pubkey")

    namespaces = []
    while node_argv:
        namespace, node_argv = parser.parse_known_args(node_argv)
        namespaces.append(namespace)
        if not namespace.subparser_name:
            break

    node_config = {}
    special_keys = [
        "listen_addrs",
        "bootstrap_peers",
        "data_dir",
        "listen_addr",
        "expected_proof_of_work",
    ]
    for namespace in namespaces:
        section = vars(namespace)
        fixed_section = {}
        for k, v in section.items():
            if k in special_keys:
                fixed_section[k.replace("_", "-")] = v
            else:
                fixed_section[k] = v

        key = fixed_section.pop("subparser_name")
        if key == "global":
            node_config.update(fixed_section)
        else:
            # doubly nested parsers are a bit tricky. we'll just force the network keys where they belong
            if key == "genesis":
                node_config["network"][key] = fixed_section
            elif key == "genesis_parameters":
                node_config["network"][key] = {"values": fixed_section}
            else:
                node_config[key] = fixed_section

    return node_config


def get_parameters_config(bootstrap_accounts):
    default_balance = CHAIN_PARAMS["defualt_bootstrap_mutez"]
    parameter_config_argv = []
    for account in bootstrap_accounts:
        account_balance = account.get("balance") or default_balance
        parameter_config_argv.extend(
            ["--bootstrap-accounts", account["key"], str(account_balance)]
        )
    return generate_parameters_config(parameter_config_argv)


def generate_parameters_config(parameters_argv):
    parser = argparse.ArgumentParser(prog="parametersconfig")
    parser.add_argument(
        "--bootstrap-accounts",
        type=str,
        nargs="+",
        action="append",
        help="public key, mutez",
    )
    parser.add_argument("--preserved-cycles", type=int, default=2)
    parser.add_argument("--blocks-per-cycle", type=int, default=8)
    parser.add_argument("--blocks-per-commitment", type=int, default=4)
    parser.add_argument("--blocks-per-roll-snapshot", type=int, default=4)
    parser.add_argument("--blocks-per-voting-period", type=int, default=64)
    parser.add_argument("--time-between-blocks", default=["10", "20"])
    parser.add_argument("--endorsers-per-block", type=int, default=32)
    parser.add_argument("--hard-gas-limit-per-operation", default="800000")
    parser.add_argument("--hard-gas-limit-per-block", default="8000000")
    parser.add_argument("--proof-of-work-threshold", default="-1")
    parser.add_argument("--tokens-per-roll", default="8000000000")
    parser.add_argument("--michelson-maximum-type-size", type=int, default=1000)
    parser.add_argument("--seed-nonce-revelation-tip", default="125000")
    parser.add_argument("--origination-size", type=int, default=257)
    parser.add_argument("--block-security-deposit", default="512000000")
    parser.add_argument("--endorsement-security-deposit", default="64000000")
    parser.add_argument("--endorsement-reward", default=["2000000"])
    parser.add_argument("--cost-per-byte", default="1000")
    parser.add_argument("--hard-storage-limit-per-operation", default="60000")
    parser.add_argument("--test-chain-duration", default="1966080")
    parser.add_argument("--quorum-min", type=int, default=2000)
    parser.add_argument("--quorum-max", type=int, default=7000)
    parser.add_argument("--min-proposal-quorum", type=int, default=500)
    parser.add_argument("--initial-endorsers", type=int, default=1)
    parser.add_argument("--delay-per-missing-endorsement", default="1")
    parser.add_argument("--baking-reward-per-endorsement", default=["200000"])

    namespace = parser.parse_args(parameters_argv)
    return vars(namespace)


#
# If CHAIN_PARAMS["genesis_block"] hasn't been specified, we
# generate a deterministic one.


def fill_in_missing_genesis_block():
    print("Ensure that we have genesis_block")
    if CHAIN_PARAMS["genesis_block"] == "YOUR_GENESIS_CHAIN_ID_HERE":
        print("  Generating missing genesis_block")
        seed = "foo"
        gbk = blake2b(seed.encode(), digest_size=32).digest()
        gbk_b58 = b58encode_check(b"\x01\x34" + gbk).decode("utf-8")
        CHAIN_PARAMS["genesis_block"] = gbk_b58


#
# flatten_accounts() turns ACCOUNTS into a more amenable data structure:
#
# We return:
#
#    [{ "name" : "baker0, "keys" : { "secret" : s1, "public" : pk0 }}]
#
# This is more natural, because secret/public keys are matches and need
# be processed together.  Neither key must be specified, later code will
# fill in the details if they are not specified.
#
# We then create any missing accounts that are refered to by
# CHAIN_PARAMS["nodes"]["baking"] to ensure that all named accounts
# exist.
#
# If we then find that we have been asked to make more bakers
# than accounts were specified, we create accounts of the form
#
# 	baker<baker num>
#
# and fill in the details appropriately.


def flatten_accounts():
    accounts = {}
    for account in ACCOUNTS:
        name, type, key, balance, bootstrap_baker = itemgetter(
            "name", "type", "key", "balance", "bootstrap_baker"
        )(account)

        if name in accounts:
            if type in accounts[name]:
                print("  WARNING: key specified twice! " + name + ":" + type)
            else:
                accounts[name][type] = key
        else:
            accounts[name] = {
                type: key,
                "balance": balance,
                "bootstrap_baker": bootstrap_baker,
            }

    i = 0
    for i, node in enumerate(CHAIN_PARAMS["nodes"]["baking"]):
        acct = node.get("bake_for", "baker" + str(i))
        if acct not in accounts:
            print("    Creating specified but missing account " + acct)
            accounts[acct] = {
                balance: CHAIN_PARAMS["defualt_bootstrap_mutez"],
                bootstrap_baker: True,
            }
    return accounts


#
# import_keys() creates three files in /var/tezos/client which specify
# the keys for each of the accounts: secret_keys, public_keys, and
# public_key_hashs.
#
# We iterate over flatten_accounts() which ensures that we
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


def import_keys(flattened_accounts):
    print("Importing keys")
    tezdir = "/var/tezos/client"
    os.makedirs(tezdir, exist_ok=True)
    os.chmod(tezdir, 0o777)
    secret_keys = []
    public_keys = []
    public_key_hashs = []
    for name, keys in flattened_accounts.items():
        print("  Making account: " + name)
        sk = pk = None
        if "secret" in keys:
            print("    Secret key specified")
            sk = b58decode_check(keys["secret"])
            if sk[0:4] != edsk:
                print("WARNING: unrecognised secret key prefix")
            sk = sk[4:]
        if "public" in keys:
            print("    Public key specified")
            pk = b58decode_check(keys["public"])
            if pk[0:4] != edpk:
                print("WARNING: unrecognised public key prefix")
            pk = pk[4:]

        if sk == None and pk == None:
            print("    Secret key derived from genesis_block")
            seed = name + ":" + CHAIN_PARAMS["genesis_block"]
            sk = blake2b(seed.encode(), digest_size=32).digest()

        if sk != None:
            if pk == None:
                print("    Deriving public key from secret key")
            tmp_pk = SigningKey(sk).verify_key.encode()
            if pk != None and pk != tmp_pk:
                print("WARNING: secret/public key mismatch for " + name)
                print("WARNING: using derived key not specified key")
            pk = tmp_pk

        pkh = blake2b(pk, digest_size=20).digest()

        pk_b58 = b58encode_check(edpk + pk).decode("utf-8")
        pkh_b58 = b58encode_check(tz1 + pkh).decode("utf-8")

        if sk != None:
            print("    Appending secret key")
            sk_b58 = b58encode_check(edsk + sk).decode("utf-8")
            secret_keys.append({"name": name, "value": "unencrypted:" + sk_b58})

        print("    Appending public key")
        public_keys.append(
            {"name": name, "value": {"locator": "unencrypted:" + pk_b58, "key": pk_b58}}
        )

        print("    Appending public key hash")
        public_key_hashs.append({"name": name, "value": pkh_b58})

    print("  Writing " + tezdir + "/secret_keys")
    json.dump(secret_keys, open(tezdir + "/secret_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_keys")
    json.dump(public_keys, open(tezdir + "/public_keys", "w"), indent=4)
    print("  Writing " + tezdir + "/public_key_hashs")
    json.dump(public_key_hashs, open(tezdir + "/public_key_hashs", "w"), indent=4)


if __name__ == "__main__":
    main()
