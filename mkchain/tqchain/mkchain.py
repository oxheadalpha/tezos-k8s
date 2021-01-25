import argparse
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


def run_docker(image, entrypoint, *args):
    return subprocess.check_output(
        "docker run --entrypoint %s --rm %s %s" % (entrypoint, image, " ".join(args)),
        stderr=subprocess.STDOUT,
        shell=True,
    )


def extract_key(keys, index: int) -> bytes:
    return keys[index].split(b":")[index].strip().decode("ascii")


def gen_key(image):
    keys = run_docker(
        image,
        "sh",
        "-c",
        "'/usr/local/bin/tezos-client --protocol PsDELPH1Kxsx gen keys mykey && /usr/local/bin/tezos-client --protocol PsDELPH1Kxsx show address mykey -S'",
    ).split(b"\n")

    return {"public": extract_key(keys, 1), "secret": extract_key(keys, 2)}


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
    "number_of_bakers": {
        "help": "number of bakers in the cluster",
        "default": 1,
        "type": int,
    },
    "zerotier_network": {"help": "Zerotier network id for external chain access"},
    "zerotier_token": {"help": "Zerotier token for external chain access"},
    "bootstrap_peer": {"help": "peer ip to join"},
    "docker_image": {
        "help": "Version of the Tezos docker image",
        "default": "tezos/tezos:v8-release",
    },
    "rpc_auth": {
        "help": "Should spin up an RPC authentication server",
        "action": "store_true",
        "default": False,
    },
}


def get_args():
    parser = argparse.ArgumentParser(
        description="Generate helm values for use with the tezos-chain helm chart"
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

    if args.number_of_nodes < 1:
        print(
            f"Invalid argument --number-of-nodes {args.number_of_nodes}, must be 1 or more"
        )
        exit(1)

    if args.number_of_bakers < 1:
        print(
            f"Invalid argument --number-of-bakers {args.number_of_bakers}, must be 1 or more"
        )
        exit(1)

    baking_accounts = [f"baker{n}" for n in range(args.number_of_bakers)]

    base_constants = {
        "chain_name": args.chain_name,
        "images": {
            "tezos": args.docker_image,
        },
        "genesis": {
            "genesis_chain_id": get_genesis_vanity_chain_id(),
            "bootstrap_timestamp": datetime.utcnow()
            .replace(tzinfo=timezone.utc)
            .isoformat(),
        },
        "zerotier_in_use": bool(args.zerotier_network),
        "rpc_auth": args.rpc_auth,
        "zerotier_config": {
            "zerotier_network": args.zerotier_network,
            "zerotier_token": args.zerotier_token,
        },
    }

    accounts = {"secret": [], "public": []}
    for account in baking_accounts:
        keys = gen_key(args.docker_image)
        for key_type in keys:
            accounts[key_type].append(
                {
                    "name": account,
                    "key": keys[key_type],
                    "type": key_type,
                }
            )

    creation_nodes = {
        "baking": [{"bake_for": f"baker{n}"} for n in range(args.number_of_bakers)],
        "regular": [{} for n in range(args.number_of_nodes - args.number_of_bakers)],
    }

    # first nodes are acting as bootstrap nodes for the others
    creation_nodes["baking"][0]["bootstrap"] = True
    if len(creation_nodes["baking"]) > 1:
        creation_nodes["baking"][1]["bootstrap"] = True

    invitation_nodes = {"baking": [], "regular": [{}]}

    bootstrap_peers = [args.bootstrap_peer] if args.bootstrap_peer else []

    creation_constants = {
        **base_constants,
        "accounts": accounts["secret"],
        "is_invitation": False,
        "bootstrap_peers": bootstrap_peers,
        "nodes": creation_nodes,
    }
    invitation_constants = {
        **base_constants,
        "accounts": accounts["public"],
        "is_invitation": True,
        "bootstrap_peers": bootstrap_peers,
        "nodes": invitation_nodes,
    }
    invitation_constants.pop("rpc_auth")

    files_path = f"{os.getcwd()}/{args.chain_name}"
    with open(f"{files_path}_values.yaml", "w") as yaml_file:
        yaml.dump(creation_constants, yaml_file)
        print(f"Wrote chain creation constants to {files_path}_values.yaml")
    with open(f"{files_path}_invite_values.yaml", "w") as yaml_file:
        print(f"Wrote chain invitation constants to {files_path}_invite_values.yaml")
        yaml.dump(invitation_constants, yaml_file)


if __name__ == "__main__":
    main()
