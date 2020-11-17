import argparse
import base64
import os
import random
import string
import subprocess
import sys
from datetime import datetime, timezone

import yaml

from ._version import get_versions

sys.path.insert(0, "tqchain")

__version__ = get_versions()["version"]


my_path = os.path.dirname(os.path.abspath(__file__))


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

    def extract_key(index: int) -> bytes:
        return base64.b64encode(
            keys[index].split(b":")[index].strip().decode("utf-8").encode("ascii")
        )

    return {"public_key": extract_key(1), "secret_key": extract_key(2)}


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
    "additional_nodes": {
        "help": "number of peers in the cluster",
        "default": 0,
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
    "zerotier_docker_image": {"help": "Docker image for zerotier connection"},
    "bootstrap_peer": {"help": "peer ip to join"},
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

    parser.add_argument("chain_name", action="store", help="Name of your chain")

    for k, v in CHAIN_CONSTANTS.items():
        parser.add_argument(*["--" + k.replace("_", "-")], **v)

    return parser.parse_args()


def main():
    args = get_args()

    bootstrap_accounts = [
        "baker",
        "bootstrap_account_1",
        "bootstrap_account_2",
        "genesis",
    ]

    zerotier_image = (
        "tezos-zerotier:dev"
        if "-" in __version__ or "+" in __version__
        else "tqtezos/tezos-k8s-zerotier:%s" % __version__
    )

    base_constants = {
        "chain_name": args.chain_name,
        "genesis_chain_id": get_genesis_vanity_chain_id(),
        "bootstrap_timestamp": datetime.utcnow()
        .replace(tzinfo=timezone.utc)
        .isoformat(),
        "zerotier_docker_image": zerotier_image,
        "zerotier_in_use": bool(args.zerotier_network),
    }
    for k in CHAIN_CONSTANTS.keys():
        if vars(args)[k] is not None:
            base_constants[k] = vars(args)[k]
    bootstraps = base64.b64encode(" ".join(bootstrap_accounts).encode("ascii"))
    secret_keys = {"BOOTSTRAP_ACCOUNTS": bootstraps}
    public_keys = {"BOOTSTRAP_ACCOUNTS": bootstraps}
    for account in bootstrap_accounts:
        keys = gen_key(args.docker_image)
        secret_keys[f"{account}_secret_key"] = keys["secret_key"]
        public_keys[f"{account}_public_key"] = keys["public_key"]

    bootstrap_peers = [args.bootstrap_peer] if args.bootstrap_peer else []

    creation_constants = {
        **base_constants,
        "keys": secret_keys,
        "is_invitation": False,
        "bootstrap_peers": bootstrap_peers + ["tezos-bootstrap-node-p2p:9732"],
    }
    invitation_constants = {
        **base_constants,
        "keys": public_keys,
        "is_invitation": True,
        "bootstrap_peers": bootstrap_peers,
    }

    with open(f"{args.chain_name}_values.yaml", "w") as yaml_file:
        yaml.dump(creation_constants, yaml_file)
        print(f"Wrote create constants in {args.chain_name}_values.yaml")
    with open(f"{args.chain_name}_invite_values.yaml", "w") as yaml_file:
        print(f"Wrote invitation constants in {args.chain_name}_invite_values.yaml")
        yaml.dump(invitation_constants, yaml_file)


if __name__ == "__main__":
    main()
