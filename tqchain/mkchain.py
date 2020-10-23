import argparse
import base64
import json
import os
import random
import string
import subprocess
import sys
import uuid
import yaml
import platform

from datetime import datetime
from datetime import timezone
from ipaddress import IPv4Address
from kubernetes import client as k8s_client
from kubernetes import config as k8s_config


my_path = os.path.dirname(os.path.abspath(__file__))


# https://stackoverflow.com/questions/25833613/python-safe-method-to-get-value-of-nested-dictionary/25833661
def safeget(dct, *keys):
    for key in keys:
        try:
            dct = dct[key]
        except KeyError:
            return None
    return dct


def run_docker(image, entrypoint, *args):
    return subprocess.check_output(
        "docker run --entrypoint %s --rm %s %s"
        % (entrypoint, image, " ".join(args)),
        stderr=subprocess.STDOUT,
        shell=True,
    )


def gen_key(image):
    keys = run_docker(
                image,
                "sh",
                "-c",
                "'/usr/local/bin/tezos-client --protocol PsCARTHAGazK gen keys mykey && /usr/local/bin/tezos-client --protocol PsCARTHAGazK show address mykey -S'"
    ).split(b"\n")
    return { "public_key":
          keys[1].split(b":")[1]
          .strip()
          .decode("utf-8"),
        "secret_key":
          keys[2].split(b":")[2]
          .strip()
          .decode("utf-8"),
        }



def get_ensure_node_dir_job():
    return [
        {
            "name": "ensure-node-dir-job",
            "image": "busybox",
            "command": ["/bin/mkdir"],
            "args": [
                "-p",
                "/var/tezos/node",
            ],
            "volumeMounts": [
                {"name": "var-volume", "mountPath": "/var/tezos"},
            ],
        }
    ]


def get_identity_job(docker_image):
    return {
        "name": "identity-job",
        "image": docker_image,
        "command": ["/bin/sh"],
        "args": [
            "-c",
            "[ -f /var/tezos/node/identity.json ] || (mkdir -p /var/tezos/node && /usr/local/bin/tezos-node identity generate 0 --data-dir /var/tezos/node --config-file /etc/tezos/config.json)"
        ],
        "volumeMounts": [
            {"name": "config-volume", "mountPath": "/etc/tezos"},
            {"name": "var-volume", "mountPath": "/var/tezos"},
        ],
    }

def get_import_key_job(docker_image):
    return {
        "name": "import-keys",
        "image": docker_image,
        "command": ["sh", "/opt/tqtezos/import_keys.sh"],
        "envFrom": [
            {"secretRef": { "name": "tezos-secret" } },
        ],
        "volumeMounts": [
            {"name": "tqtezos-utils", "mountPath": "/opt/tqtezos"},
            {"name": "var-volume", "mountPath": "/var/tezos"},
        ],
    }

def get_baker(docker_image, baker_command):
    return {
        "name": "baker-job",
        "image": docker_image,
        "command": [baker_command],
        "args": [
            "-A",
            "localhost",
            "-P",
            "8732",
            "-d",
            "/var/tezos/client",
            "run",
            "with",
            "local",
            "node",
            "/var/tezos/node",
            "baker",
        ],
        "volumeMounts": [{"name": "var-volume", "mountPath": "/var/tezos"}],
    }


def get_endorser(docker_image, endorser_command):
    return {
        "name": "endorser",
        "image": docker_image,
        "command": [endorser_command],
        "args": [
            "-A",
            "localhost",
            "-P",
            "8732",
            "-d",
            "/var/tezos/client",
            "run",
            "baker",
        ],
        "volumeMounts": [{"name": "var-volume", "mountPath": "/var/tezos"}],
    }



def get_genesis_vanity_chain_id(seed_len=16):
    seed = "".join(
        random.choice(string.ascii_uppercase + string.digits) for _ in range(seed_len)
    )

    FLEXTESA = "registry.gitlab.com/tezos/flextesa:01e3f596-run"
    return (
        run_docker(
            FLEXTESA,
            "flextesa",
            "vani",
            '""',
            "--seed",
            seed,
            "--first",
            "--machine-readable",
            "csv",
        )
        .decode("utf-8")
        .split(",")[1]
    )




def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("chain_name")

    parser.add_argument("--baker", action="store_true")
    parser.add_argument("--docker-image", default="tezos/tezos:v7-release")
    parser.add_argument("--bootstrap-mutez", default="4000000000000")

    parser.add_argument("--zerotier-network")
    parser.add_argument("--zerotier-token")

    group = parser.add_mutually_exclusive_group()
    group.add_argument("--generate-constants", action="store_true", help="Generate constants that uniquely define the private chain")
    group.add_argument("--create", action="store_true", help="Create a private chain")
    group.add_argument(
        "--invite", action="store_true", help="Invite someone to join a private chain"
    )

    subparsers = parser.add_subparsers(help="clusters")

    parser.add_argument("--number-of-nodes", help="number of peers in the cluster", default=1, type=int)
    parser.add_argument("--bootstrap-peer", help="peer ip to join")
    parser.add_argument(
        "--genesis-key", help="genesis public key for the chain to join"
    )
    parser.add_argument("--genesis-block", help="hash of the genesis block")
    parser.add_argument("--timestamp", help="timestamp for the chain to join")

    parser.add_argument(
        "--protocol-hash", default="PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb"
    )
    parser.add_argument("--baker-command", default="tezos-baker-006-PsCARTHA")

    parser.add_argument("--cluster", default="minikube")

    return parser.parse_args()


def main():
    args = get_args()

    bootstrap_peers = []
    bootstrap_accounts = ["baker", "bootstrap_account_1", "bootstrap_account_2", "genesis"]
    k8s_templates = ["common.yaml"]

    zerotier_network = args.zerotier_network
    zerotier_token = args.zerotier_token

    if args.number_of_nodes < 1:
        print(f"Invalid argument --number-of-nodes {arg.number_of_nodes}, must be 1 or more")
        exit(1)

    if args.create or args.invite:
        if not os.path.isfile(f"{args.chain_name}_chain.yaml"):
            print(f"Could not find the constants file {args.chain_name}_chain.yaml, did you run mkchain --generate-constants <chain_name> ?",
                    file=sys.stderr)
            exit(1)

    if args.create:
        with open(f"{args.chain_name}_chain.yaml", "r") as yaml_file:
            constants = yaml.safe_load(yaml_file)

    if args.invite:
        with open(f"{args.chain_name}_chain_invite.yaml", "r") as yaml_file:
            constants = yaml.safe_load(yaml_file)

    if args.generate_constants:
        base_constants = {
            "genesis_chain_id": get_genesis_vanity_chain_id(),
            "bootstrap_timestamp": datetime.utcnow().replace(tzinfo=timezone.utc).isoformat(),
        }
        secret_keys = {}
        public_keys = {}
        for account in bootstrap_accounts:
            keys = gen_key(args.docker_image)
            secret_keys[f"{account}_secret_key"] = keys["secret_key"]
            public_keys[f"{account}_public_key"] = keys["public_key"]

        creation_constants = { **base_constants, **secret_keys }
        invitation_constants = { **base_constants, **public_keys }

        with open(f"{args.chain_name}_chain.yaml", "w") as yaml_file:
            yaml.dump(creation_constants,yaml_file)
        with open(f"{args.chain_name}_chain_invite.yaml", "w") as yaml_file:
            yaml.dump(invitation_constants,yaml_file)
        exit(0)

    if args.create:
        k8s_templates.append("bootstrap-node.yaml")
        bootstrap_peers = []
        if args.number_of_nodes > 1:
            k8s_templates.append("node.yaml")
            bootstrap_peers.append("tezos-bootstrap:9732")

    if args.invite:
        k8s_templates.append("node.yaml")
        k8s_config.load_kube_config()
        v1 = k8s_client.CoreV1Api()
        bootstrap_peer = args.bootstrap_peer
        node_port = (
            v1.read_namespaced_service("tezos-bootstrap", "tqtezos")
            .spec.ports[0]
            .node_port
        )
        bootstrap_peers = [f"{bootstrap_peer}:{node_port}"]

        zerotier_config = v1.read_namespaced_config_map('zerotier-config', 'tqtezos')
        zerotier_network = zerotier_config.data['NETWORK_IDS']
        zerotier_token = zerotier_config.data['ZTAUTHTOKEN']

    if zerotier_network:
        k8s_templates.append("zerotier.yaml")

    k8s_objects = []
    for template in k8s_templates:
        with open(os.path.join(my_path, "deployment", template), "r") as yaml_template:

            k8s_resources = yaml.load_all(yaml_template, Loader=yaml.FullLoader)
            for k in k8s_resources:

                if safeget(k, "metadata", "name") == "tezos-pv-claim":
                    if args.cluster == "eks":
                        k["spec"]["storageClassName"] = "gp2"

                if safeget(k, "metadata", "name") == "tezos-secret":
                    data = { "BOOTSTRAP_ACCOUNTS" : " ".join(bootstrap_accounts) }
                    if args.create:
                        data["KEYS_TYPE"] = "secret"
                        for account in bootstrap_accounts + ["genesis"]:
                            data[account + "_secret_key"] = constants[f"{account}_secret_key"]
                    if args.invite:
                        data["KEYS_TYPE"] = "public"
                        for account in bootstrap_accounts + ["genesis"]:
                            data[account + "_public_key"] = constants[f"{account}_public_key"]
                    k["data"] = { k:base64.b64encode(v.encode("ascii")) for (k,v) in data.items() }

                if safeget(k, "metadata", "name") == "tezos-config":
                    k["data"] = {
                        "CHAIN_PARAMS": json.dumps(
                            { "bootstrap_mutez": args.bootstrap_mutez,
                              "chain_name": args.chain_name,
                              "bootstrap_peers": bootstrap_peers,
                              "genesis_block": constants["genesis_chain_id"],
                              "timestamp": constants["bootstrap_timestamp"],
                            }
                        ),
                    }

                if safeget(k, "metadata", "name") == "tqtezos-utils":
                    with open(os.path.join(my_path, "utils/import_keys.sh"), "r") as import_file:
                        import_key_script = import_file.read()
                    with open(os.path.join(my_path, "utils/generateTezosConfig.py"), "r") as import_file:
                        generate_tezos_config_script = import_file.read()
                    k["data"] = {
                        "import_keys.sh": import_key_script,
                        "generateTezosConfig.py": generate_tezos_config_script,
                    }

                if safeget(k, "metadata", "name") == "tezos-bootstrap-node":
                    # set the docker image for the node
                    k["spec"]["template"]["spec"]["containers"][0][
                        "image"
                    ] = args.docker_image

                    # add key import for bootstrap node
                    k["spec"]["template"]["spec"][
                        "initContainers"
                    ].insert(0, get_import_key_job(args.docker_image))

                    # add the identity job
                    k["spec"]["template"]["spec"][
                        "initContainers"
                    ].append(get_identity_job(args.docker_image))

                    if args.baker:
                        k["spec"]["template"]["spec"]["containers"].append(
                            get_baker(args.docker_image, args.baker_command)
                        )

                if safeget(k, "metadata", "name") == "tezos-node":
                    # set the docker image for the node
                    k["spec"]["template"]["spec"]["containers"][0][
                        "image"
                    ] = args.docker_image

                    # add key import for bootstrap node
                    k["spec"]["template"]["spec"][
                        "initContainers"
                    ].insert(0, get_import_key_job(args.docker_image))

                    # add the identity job
                    k["spec"]["template"]["spec"][
                        "initContainers"
                    ].append(get_identity_job(args.docker_image))

                    # set replicas
                    k["spec"]["replicas"] = args.number_of_nodes - ( 1 if args.create else 0 )

                if safeget(k, "metadata", "name") == "activate-job":
                    k["spec"]["template"]["spec"]["initContainers"][0][
                        "image"
                    ] = args.docker_image
                    k["spec"]["template"]["spec"]["initContainers"][3][
                        "image"
                    ] = args.docker_image
                    k["spec"]["template"]["spec"]["initContainers"][3]["args"] = [
                        "-A",
                        "tezos-bootstrap-node-rpc",
                        "-P",
                        "8732",
                        "-d",
                        "/var/tezos/client",
                        "-l",
                        "--block",
                        "genesis",
                        "activate",
                        "protocol",
                        args.protocol_hash,
                        "with",
                        "fitness",
                        "-1",
                        "and",
                        "key",
                        "genesis",
                        "and",
                        "parameters",
                        "/etc/tezos/parameters.json",
                    ]
                    k["spec"]["template"]["spec"]["initContainers"][4][
                        "image"
                    ] = args.docker_image

                    if args.cluster == "minikube":
                        k["spec"]["template"]["spec"]["volumes"][1] = {
                           "name": "var-volume",
                           "persistentVolumeClaim": {
                             "claimName": "tezos-bootstrap-node-pv-claim" } }

                if safeget(k, "metadata", "name") == "zerotier-config":
                    k["data"]["NETWORK_IDS"] = zerotier_network
                    k["data"]["ZTAUTHTOKEN"] = zerotier_token
                    zt_hostname = str(uuid.uuid4())
                    print(f"zt_hostname: {zt_hostname}", file=sys.stderr)
                    k["data"]["ZTHOSTNAME"] = zt_hostname

                k8s_objects.append(k)

    yaml.dump_all(k8s_objects, sys.stdout)


if __name__ == "__main__":
    main()
