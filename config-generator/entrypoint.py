import argparse
import json
import os
import socket

CHAIN_PARAMS = json.loads(os.environ["CHAIN_PARAMS"])


def main():
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

    bootstrap_accounts = get_bootstrap_account_pubkeys()
    if main_args.generate_parameters_json:
        parameters_json = json.dumps(
            get_parameters_config(
                [*bootstrap_accounts.values()],
                CHAIN_PARAMS["bootstrap_mutez"],
            ),
            indent=2,
        )
        print("Generated parameters.json :")
        print(parameters_json)
        with open("/etc/tezos/parameters.json", "w") as json_file:
            print(parameters_json, file=json_file)

    if main_args.generate_config_json:
        net_addr = None
        bootstrap_peers = CHAIN_PARAMS.get("bootstrap_peers", [])
        if CHAIN_PARAMS["chain_type"] == "private":
            with open("/var/tezos/zerotier_data.json", "r") as f:
                net_addr = json.load(f)[0]["assignedAddresses"][0].split("/")[0]
            if bootstrap_peers == []:
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())
        else:
            local_bootstrap_peers = []
            for i, node in enumerate(CHAIN_PARAMS["nodes"]["baking"]):
                if (
                    node.get("bootstrap", False)
                    and f"tezos-baking-node-{i}" not in socket.gethostname()
                ):
                    local_bootstrap_peers.append(
                        f"tezos-baking-node-{i}.tezos-baking-node:9732"
                    )
            bootstrap_peers.extend(local_bootstrap_peers)

        config_json = json.dumps(
            get_node_config(
                CHAIN_PARAMS["chain_name"],
                bootstrap_accounts[CHAIN_PARAMS["activation_account"]],
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


def get_bootstrap_account_pubkeys():
    with open("/var/tezos/client/public_keys", "r") as f:
        tezos_pubkey_list = json.load(f)
    pubkeys = {}
    for key in tezos_pubkey_list:
        pubkeys[key["name"]] = key["value"]["key"]
    return pubkeys


def get_node_config(
    chain_name,
    genesis_key,
    timestamp,
    bootstrap_peers,
    genesis_block=None,
    net_addr=None,
):

    node_config = { "data-dir": "/var/tezos/node",
            "rpc": {
                "listen-addrs": [f"{os.getenv('MY_POD_IP')}:8732", "127.0.0.1:8732"],
                },
            "p2p": {
                "expected-proof-of-work": 0,
                "listen-addr": ( net_addr + ":9732" if net_addr else "[::]:9732" )
                }
            }
    if CHAIN_PARAMS["chain_type"] == "public":
        node_config["network"] = CHAIN_PARAMS["network"]
    else:
        node_config["p2p"]["bootstrap-peers"] = bootstrap_nodes
        node_config["network"] = {
                "chain_name": chain_name,
                "sandboxed_chain_name": "SANDBOZED_TEZOS",
                "default_bootstrap_peers": [],
                "genesis": {
                    "timestamp": timestamp,
                    "block": genesis_block,
                    "protocol": "PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex"
                    },
                "genesis_parameters": {
                    "values": {
                        "genesis_pubkey": genesis_key,
                    },
                },
            }

    return node_config


def get_parameters_config(bootstrap_accounts, bootstrap_mutez):
    parameter_config_argv = []
    for bootstrap_account in bootstrap_accounts:
        parameter_config_argv.extend(
            [
                "--bootstrap-accounts",
                bootstrap_account,
                bootstrap_mutez,
            ]
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


if __name__ == "__main__":
    main()
