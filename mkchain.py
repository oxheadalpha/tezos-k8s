import argparse
import datetime
import json
import os
import subprocess
import sys
from ipaddress import IPv4Address

common_templates = ["deployment/tznode.yaml"]
local_templates = []
eks_templates = []

my_path = os.path.abspath(os.path.dirname(__file__))
init_path = os.path.join(my_path, "scripts", "tzinit.sh")
tezos_dir = os.path.expanduser("~/.tq/")
config_path = os.path.join(tezos_dir, "node", "config.json")
parameters_path = os.path.join(tezos_dir, "client", "parameters.json")


def run_docker(entrypoint, mount, *args, image="tezos/tezos:v7-release"):
    subprocess.check_output(
        "docker run --entrypoint %s -u %s --rm -v %s %s %s"
        % (entrypoint, os.getuid(), mount, image, " ".join(args)),
        shell=True,
    )


def gen_key(client_dir, key_name):
    entrypoint = "/usr/local/bin/tezos-client"
    mount = client_dir + ":/data"
    run_docker(
        entrypoint,
        mount,
        "-d",
        "/data",
        "--protocol",
        "PsCARTHAGazK",
        "gen",
        "keys",
        key_name,
        "--force",
    )


def get_key(client_dir, name):
    with open(os.path.join(client_dir, "public_keys"), "r") as keyfile:
        keys = json.load(keyfile)
        offset = 0
        for key in keys:
            if key["name"] == name:
                value = key["value"]
                if value.startswith("unencrypted:"):
                    offset = len("unencrypted:")
                return value[offset:]


def gen_id(node_dir):
    entrypoint = "/usr/local/bin/tezos-node"
    mount = node_dir + ":/data"
    run_docker(
        entrypoint,
        mount,
        "identity",
        "generate",
        "0",
        "--data-dir",
        "/data",
        "--config-file",
        "/data/config.json",
    )


# FIXME - this should probably be replaced with subprocess calls to tezos-node config
def generate_node_config(node_argv):
    parser = argparse.ArgumentParser(prog="nodeconfig")
    subparsers = parser.add_subparsers(help="sub-command help", dest="subparser_name")

    global_parser = subparsers.add_parser("global")
    global_parser.add_argument("--data-dir", default="/var/tezos/node")

    rpc_parser = subparsers.add_parser("rpc")
    rpc_parser.add_argument("--listen-addrs", action="append", default=[":8733"])

    p2p_parser = subparsers.add_parser("p2p")
    p2p_parser.add_argument("--bootstrap-peers", action="append", default=[])
    p2p_parser.add_argument("--listen-addr", default="[::]:8732")
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
    parser.add_argument("--proof-of-work-threshold", default="0")
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


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("chain_name")
    parser.add_argument("--tezos-dir", default=tezos_dir)

    subparsers = parser.add_subparsers(help="targets")
    create_parser = subparsers.add_parser("create", help="Create a private chain")
    create_parser.set_defaults(create=True)

    join_parser = subparsers.add_parser("join", help="Join a private chain")
    join_parser.set_defaults(join=True)
    join_parser.add_argument("bootstrap_peer", help="peer ip")
    join_parser.add_argument("genesis_key", help="genesis public key for the chain")
    join_parser.add_argument("timestamp", help="timestamp for the chain")

    parser.add_argument("--stdout", action="store_true")
    parser.add_argument(
        "--protocol-hash", default="PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb"
    )
    parser.add_argument(
        "--docker-image", default="tezos/tezos:v7.0-rc1_cde7fbbb_20200416150132"
    )

    parser_minikube = subparsers.add_parser(
        "minikube", help="generate config for Minikube"
    )
    parser_minikube.add_argument(
        "-t", "--template", action="append", default=common_templates + local_templates
    )
    parser_minikube.set_defaults(minikube=True)

    parser_eks = subparsers.add_parser("eks", help="generate config for EKS")
    parser_eks.add_argument(
        "-t", "--template", action="append", default=common_templates + eks_templates
    )
    parser_eks.add_argument("gdb_volume_id")
    parser_eks.add_argument("gdb_aws_region")

    return parser.parse_args()


def write_node_config(node_dir, chain_name, genesis_key, timestamp, bootstrap_peers):

    p2p = ["p2p"]
    for bootstrap_peer in bootstrap_peers:
        p2p.extend(["--bootstrap-peers", bootstrap_peer])

    node_config_args = p2p + [
        "global",
        "rpc",
        "network",
        "--chain-name",
        chain_name,
        "genesis",
        "--timestamp",
        timestamp,
        "genesis_parameters",
        "--genesis-pubkey",
        genesis_key,
    ]
    print("node config args: %r" % node_config_args)
    node_config = generate_node_config(node_config_args)

    with open(os.path.join(node_dir, "config.json"), "w") as f:
        json.dump(node_config, f)


def write_parameters_config(client_dir, bootstrap_accounts):
    parameter_config_argv = []
    for account in bootstrap_accounts:
        parameter_config_argv.extend(["--bootstrap-accounts", account, get_key(client_dir, account)])
    parameters_config = generate_parameters_config(parameter_config_argv)
    with open(os.path.join(client_dir, "parameters.json"), "w") as f:
        json.dump(parameters_config, f)


def main():
    args = get_args()

    if os.path.exists(args.tezos_dir):
        raise Exception(
            "detected existing installation, please remove it first: %s"
            % (args.tezos_dir)
        )
    node_dir = os.path.join(args.tezos_dir, "node")
    client_dir = os.path.join(args.tezos_dir, "client")
    os.makedirs(node_dir)
    os.makedirs(client_dir)

    genesis_key = None
    timestamp = None
    bootstrap_peers = []
    bootstrap_accounts = ["bootstrap_account_1", "bootstrap_account_2", "bootstrap_account_3"]

    if "create" in args:
        for account in bootstrap_accounts + ["genesis"]:
            gen_key(client_dir, account)
        timestamp = (
            datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc).isoformat()
        )
        genesis_key = get_key(client_dir, "genesis")
        bootstrap_peers = []

        write_parameters_config(client_dir, bootstrap_accounts)

    if "join" in args:
        genesis_key = args.genesis_key
        # validate peer ip
        bootstrap_peers = [str(IPv4Address(args.bootstrap_peer))]
        timestamp = args.timestamp

    # generate the id for the node.
    write_node_config(
        node_dir, args.chain_name, genesis_key, timestamp, bootstrap_peers
    )
    gen_id(node_dir)

    # if args.get("minikube"):
    #     try:
    #         minikube_route = subprocess.check_output(
    #             '''minikube ssh "route -n | grep ^0.0.0.0"''', shell=True
    #         ).split()
    #         minkube_gw, minicube_iface = minikube_route[0], minikube_route[7]
    #         minikube_ip = subprocess.check_output(
    #             '''minikube ssh "ip addr show eth0|awk /^[[:space:]]+inet/'{print \$2}'"''',
    #             shell=True,
    #         ).split(b"/")[0]
    #     except subprocess.CalledProcessError as e:
    #         print("failed to get minikube route %r" % e)

    # if args["create"]:
    #     subprocess.check_output(
    #         "%s --chain-name %s --work-dir %s"
    #         % (init_path, args["chain_name"], args["tezos_dir"]),
    #         shell=True,
    #     )
    #     args["template"].append("deployment/activate.yaml")

    # # assign the contents of config.json to a template variable for the ConfigMap
    # args["config_json"] = json.dumps(json.load(open(args["config_file"], "r")))
    # args["parameters_json"] = json.dumps(json.load(open(args["parameters_file"], "r")))

    # if args["stdout"]:
    #     out = sys.stdout
    # else:
    #     out = open("tq-{}.yaml".format(args["chain_name"]), "wb")

    # with out as yaml_file:
    #     for template in args["template"]:
    #         with open(template) as template_file:
    #             template = template_file.read()
    #             out_yaml = template.format(**args)
    #         yaml_file.write(out_yaml.encode("utf-8"))
    #         yaml_file.write(b"\n---\n")


if __name__ == "__main__":
    main()
