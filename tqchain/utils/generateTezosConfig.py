#!/bin/python
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
        bootstrap_peers = CHAIN_PARAMS["bootstrap_peers"]
        if CHAIN_PARAMS["zerotier_in_use"]:
            with open("/var/tezos/zerotier_data.json", "r") as f:
                net_addr = json.load(f)[0]["assignedAddresses"][0].split("/")[0]
            if bootstrap_peers == [] and "bootstrap" not in socket.gethostname():
                bootstrap_peers.extend(get_zerotier_bootstrap_peer_ips())

        config_json = json.dumps(
            get_node_config(
                CHAIN_PARAMS["chain_name"],
                bootstrap_accounts["genesis"],
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
    rpc_parser.add_argument("--listen-addrs", action="append", default=["0.0.0.0:8732"])

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
