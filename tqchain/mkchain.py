import argparse
import base64
import json
import os
import random
import string
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, "tqchain")
from ._version import get_versions

__version__ = get_versions()["version"]

import yaml

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
        "docker run --entrypoint %s --rm %s %s" % (entrypoint, image, " ".join(args)),
        stderr=subprocess.STDOUT,
        shell=True,
    )


def gen_key(image):
    keys = run_docker(
        image,
        "sh",
        "-c",
        "'/usr/local/bin/tezos-client --protocol PsCARTHAGazK gen keys mykey && /usr/local/bin/tezos-client --protocol PsCARTHAGazK show address mykey -S'",
    ).split(b"\n")
    return {
        "public_key": keys[1].split(b":")[1].strip().decode("utf-8"),
        "secret_key": keys[2].split(b":")[2].strip().decode("utf-8"),
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
            "[ -f /var/tezos/node/identity.json ] || (mkdir -p /var/tezos/node && /usr/local/bin/tezos-node identity generate 0 --data-dir /var/tezos/node --config-file /etc/tezos/config.json)",
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
            {"secretRef": {"name": "tezos-secret"}},
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


def get_zerotier_initcontainer():
    return {
        "name": "get-zerotier-ip",
        "image": (
            "tezos-zerotier:dev"
            if "-" in __version__ or "+" in __version__
            else "tqtezos/tezos-k8s-zerotier:%s" % __version__
        ),
        "imagePullPolicy": "IfNotPresent",
        "envFrom": [
            {"configMapRef": {"name": "zerotier-config"}},
        ],
        "securityContext": {
            "privileged": True,
            "capabilities": {
                "add": ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"],
            },
        },
        "volumeMounts": [
            {"name": "tqtezos-utils", "mountPath": "/opt/tqtezos"},
            {"name": "var-volume", "mountPath": "/var/tezos"},
            {"name": "dev-net-tun", "mountPath": "/dev/net/tun"},
        ],
    }


def get_zerotier_container():
    return {
        "name": "zerotier",
        "image": (
            "tezos-zerotier:dev"
            if "-" in __version__ or "+" in __version__
            else "tqtezos/tezos-k8s-zerotier:%s" % __version__
        ),
        "imagePullPolicy": "IfNotPresent",
        "command": ["sh"],
        "args": [
            "-c",
            "echo 'starting zerotier' && zerotier-one /var/tezos/zerotier",
            "-P",
            "8732",
            "-d",
            "/var/tezos/client",
            "run",
            "baker",
        ],
        "securityContext": {
            "privileged": True,
            "capabilities": {
                "add": ["NET_ADMIN", "NET_RAW", "SYS_ADMIN"],
            },
        },
        "volumeMounts": [
            {"name": "var-volume", "mountPath": "/var/tezos"},
        ],
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


CHAIN_CONSTANTS = {
    "number_of_nodes": {
        "help": "number of peers in the cluster",
        "default": 1,
        "type": int,
    },
    "baker": {
        "help": "Include a baking node in the cluster",
        "default": True,
        "action": "store_true",
    },
    "docker_image": {
        "help": "Version of the Tezos docker image",
        "default": "tezos/tezos:v7-release",
    },
    "bootstrap_mutez": {
        "help": "Initial balance of the bootstrap accounts",
        "default": "4000000000000",
    },
    "zerotier_network": {"help": "Zerotier network id for external chain access"},
    "zerotier_token": {"help": "Zerotier token for external chain access"},
    "bootstrap_peer": {"help": "peer ip to join"},
    "genesis_key": {"help": "genesis public key for the chain to join"},
    "genesis_block": {"help": "hash of the genesis block"},
    "timestamp": {"help": "timestamp for the chain to join"},
    "protocol_hash": {
        "help": "Desired Tezos protocol hash",
        "default": "PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb",
    },
    "baker_command": {
        "help": "The baker command to use, including protocol",
        "default": "tezos-baker-006-PsCARTHA",
    },
}


def get_args():
    parser = argparse.ArgumentParser(
        description="Deploys a private Tezos chain on Kuberenetes"
    )
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s {version}".format(version=__version__),
    )
    subparsers = parser.add_subparsers(
        help="See contextual help with mkchain <action> -h", dest="action"
    )

    subparser_instances = {
        "generate-constants": "Generate constants that uniquely define your chain",
        "create": "Create a chain based on constants file",
        "invite": "Generate yaml to invite someone to your chain",
    }

    for command, help in subparser_instances.items():
        subparser = subparsers.add_parser(command, description=help, help=help)
        subparser.add_argument("chain_name", action="store", help="Name of your chain")
        for k, v in CHAIN_CONSTANTS.items():
            if command != "generate-constants":
                v.pop("default", None)
            subparser.add_argument(*["--" + k.replace("_", "-")], **v)

    return parser.parse_args()


def main():
    args = get_args()

    bootstrap_accounts = [
        "baker",
        "bootstrap_account_1",
        "bootstrap_account_2",
        "genesis",
    ]
    k8s_templates = ["common.yaml", "node.yaml"]

    if args.action in ["create", "invite"]:
        if not os.path.isfile(f"{args.chain_name}_chain.yaml"):
            print(
                f"Could not find the constants file {args.chain_name}_chain.yaml, did you run mkchain --generate-constants <chain_name> ?",
                file=sys.stderr,
            )
            exit(1)

    if args.action == "create":
        with open(f"{args.chain_name}_chain.yaml", "r") as yaml_file:
            yaml_constants = yaml.safe_load(yaml_file)

    if args.action == "invite":
        with open(f"{args.chain_name}_chain_invite.yaml", "r") as yaml_file:
            yaml_constants = yaml.safe_load(yaml_file)

    if args.action == "generate-constants":
        base_constants = {
            "genesis_chain_id": get_genesis_vanity_chain_id(),
            "bootstrap_timestamp": datetime.utcnow()
            .replace(tzinfo=timezone.utc)
            .isoformat(),
        }
        for k in CHAIN_CONSTANTS.keys():
            if vars(args)[k]:
                base_constants[k] = vars(args)[k]
        secret_keys = {}
        public_keys = {}
        for account in bootstrap_accounts:
            keys = gen_key(args.docker_image)
            secret_keys[f"{account}_secret_key"] = keys["secret_key"]
            public_keys[f"{account}_public_key"] = keys["public_key"]

        creation_constants = {**base_constants, **secret_keys}
        invitation_constants = {**base_constants, **public_keys}

        with open(f"{args.chain_name}_chain.yaml", "w") as yaml_file:
            yaml.dump(creation_constants, yaml_file)
            print(f"Wrote create constants in {args.chain_name}_chain.yaml")
        with open(f"{args.chain_name}_chain_invite.yaml", "w") as yaml_file:
            print(f"Wrote invitation constants in {args.chain_name}_chain_invite.yaml")
            yaml.dump(invitation_constants, yaml_file)
        exit(0)

    c = {
        k: (vars(args)[k] if k in vars(args) and vars(args)[k] else yaml_constants[k])
        for k in yaml_constants.keys()
    }

    if c["number_of_nodes"] < 1:
        print(
            f"Invalid argument --number-of-nodes {c['number_of_nodes']}, must be 1 or more"
        )
        exit(1)

    bootstrap_peers = [c["bootstrap_peer"]] if c.get("bootstrap_peer") else []
    if args.action == "create":
        k8s_templates.append("bootstrap-node.yaml")
        if "zerotier_network" not in c:
            bootstrap_peers.append("tezos-bootstrap-node-p2p:9732")

    if "zerotier_network" in c:
        k8s_templates.append("zerotier.yaml")

    k8s_objects = []
    for template in k8s_templates:
        with open(os.path.join(my_path, "deployment", template), "r") as yaml_template:

            k8s_resources = yaml.load_all(yaml_template, Loader=yaml.FullLoader)
            for k in k8s_resources:

                if safeget(k, "metadata", "name") == "tezos-secret":
                    data = {"BOOTSTRAP_ACCOUNTS": " ".join(bootstrap_accounts)}
                    if args.action == "create":
                        data["KEYS_TYPE"] = "secret"
                        for account in bootstrap_accounts + ["genesis"]:
                            data[account + "_secret_key"] = c[f"{account}_secret_key"]
                    if args.action == "invite":
                        data["KEYS_TYPE"] = "public"
                        for account in bootstrap_accounts + ["genesis"]:
                            data[account + "_public_key"] = c[f"{account}_public_key"]
                    k["data"] = {
                        k: base64.b64encode(v.encode("ascii"))
                        for (k, v) in data.items()
                    }

                if safeget(k, "metadata", "name") == "tezos-config":
                    k["data"] = {
                        "CHAIN_PARAMS": json.dumps(
                            {
                                "bootstrap_mutez": c["bootstrap_mutez"],
                                "chain_name": args.chain_name,
                                "bootstrap_peers": bootstrap_peers,
                                "genesis_block": c["genesis_chain_id"],
                                "timestamp": c["bootstrap_timestamp"],
                                "zerotier_in_use": c.get("zerotier_network") != None,
                            }
                        ),
                    }

                if safeget(k, "metadata", "name") == "tqtezos-utils":
                    with open(
                        os.path.join(my_path, "utils/import_keys.sh"), "r"
                    ) as import_file:
                        import_key_script = import_file.read()
                    with open(
                        os.path.join(my_path, "utils/generateTezosConfig.py"), "r"
                    ) as import_file:
                        generate_tezos_config_script = import_file.read()
                    k["data"] = {
                        "import_keys.sh": import_key_script,
                        "generateTezosConfig.py": generate_tezos_config_script,
                    }

                if safeget(k, "metadata", "name") == "tezos-bootstrap-node":
                    # set the docker image for the node
                    k["spec"]["template"]["spec"]["containers"][0]["image"] = c[
                        "docker_image"
                    ]

                    # add key import for bootstrap node
                    k["spec"]["template"]["spec"]["initContainers"].insert(
                        0, get_import_key_job(c["docker_image"])
                    )

                    # add the identity job
                    k["spec"]["template"]["spec"]["initContainers"].append(
                        get_identity_job(c["docker_image"])
                    )

                    if c["baker"]:
                        k["spec"]["template"]["spec"]["containers"].append(
                            get_baker(c["docker_image"], c["baker_command"])
                        )

                    if "zerotier_network" in c:
                        # add the zerotier containers
                        k["spec"]["template"]["spec"]["initContainers"].insert(
                            0, get_zerotier_initcontainer()
                        )

                        k["spec"]["template"]["spec"]["containers"].append(
                            get_zerotier_container()
                        )

                if safeget(k, "metadata", "name") == "tezos-node":
                    # set the docker image for the node
                    k["spec"]["template"]["spec"]["containers"][0]["image"] = c[
                        "docker_image"
                    ]

                    # add key import for peer node
                    k["spec"]["template"]["spec"]["initContainers"].insert(
                        0, get_import_key_job(c["docker_image"])
                    )

                    # add the identity job
                    k["spec"]["template"]["spec"]["initContainers"].append(
                        get_identity_job(c["docker_image"])
                    )

                    if "zerotier_network" in c:
                        # add the zerotier containers
                        k["spec"]["template"]["spec"]["initContainers"].insert(
                            0, get_zerotier_initcontainer()
                        )

                        k["spec"]["template"]["spec"]["containers"].append(
                            get_zerotier_container()
                        )

                    # set replicas
                    k["spec"]["replicas"] = c["number_of_nodes"] - (
                        1 if args.action == "create" else 0
                    )

                if safeget(k, "metadata", "name") == "activate-job":
                    k["spec"]["template"]["spec"]["initContainers"][0]["image"] = c[
                        "docker_image"
                    ]
                    k["spec"]["template"]["spec"]["initContainers"][3]["image"] = c[
                        "docker_image"
                    ]
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
                        c["protocol_hash"],
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
                    k["spec"]["template"]["spec"]["initContainers"][4]["image"] = c[
                        "docker_image"
                    ]

                if safeget(k, "metadata", "name") == "zerotier-config":
                    k["data"]["NETWORK_ID"] = c["zerotier_network"]
                    k["data"]["ZTAUTHTOKEN"] = c["zerotier_token"]
                    k["data"]["CHAIN_NAME"] = args.chain_name

                k8s_objects.append(k)

    yaml.dump_all(k8s_objects, sys.stdout)


if __name__ == "__main__":
    main()
