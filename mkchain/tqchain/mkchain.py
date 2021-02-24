import argparse
import os
import sys
from datetime import datetime, timezone

import yaml

from ._version import get_versions

sys.path.insert(0, "tqchain")

__version__ = get_versions()["version"]

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

    if args.number_of_nodes < 0:
        print(
            f"Invalid argument --number-of-nodes ({args.number_of_nodes}) "
            f"must be non-negative"
        )
        exit(1)

    if args.number_of_bakers < 0:
        print(
            f"Invalid argument --number-of-bakers ({args.number_of_bakers}) "
            f"must be non-negative"
        )
        exit(1)

    if args.number_of_nodes + args.number_of_bakers < 1:
        print(
            f"Invalid arguments: either "
            f"--number-of-nodes ({args.number_of_nodes}) or "
            f"--number-of-bakers ({args.number_of_bakers}) must be non-zero"
        )
        exit(1)

    base_constants = {
        "chain_name": args.chain_name,
        "images": {
            "tezos": args.docker_image,
        },
        "zerotier_in_use": bool(args.zerotier_network),
        "rpc_auth": args.rpc_auth,
        "zerotier_config": {
            "zerotier_network": args.zerotier_network,
            "zerotier_token": args.zerotier_token,
        },
    }

    # preserve pre-existing values, if any (in case of scale-up)
    old_create_values = {}
    files_path = f"{os.getcwd()}/{args.chain_name}"
    if os.path.isfile(f"{files_path}_values.yaml"):
        print(
            "Found old values file. Some pre-existing values will remain the "
            "same, e.g. public/private keys. Please delete the values file to "
            "generate all new values.\n"
        )
        with open(f"{files_path}_values.yaml", "r") as yaml_file:
            old_create_values = yaml.safe_load(yaml_file)
        if len(old_create_values["nodes"]["baking"]) != args.number_of_bakers:
            print("ERROR: the number of bakers must not change on a pre-existing chain")
            exit(1)
        with open(f"{files_path}_invite_values.yaml", "r") as yaml_file:
            old_invite_values = yaml.safe_load(yaml_file)

    if old_create_values.get("genesis", None):
        base_constants["genesis"] = old_create_values["genesis"]
    else:
        # create new chain genesis params if brand new chain
        base_constants["genesis"] = {
            "timestamp": datetime.utcnow().replace(tzinfo=timezone.utc).isoformat(),
        }

    # These accounts are only what users manually added to values.yaml and
    # invite_values.yaml.
    accounts = {"secret": [], "public": []}
    if old_create_values.get("accounts", None):
        accounts["secret"] = old_create_values["accounts"]
        accounts["public"] = old_invite_values["accounts"]

    creation_nodes = {
        "baking": [{"bake_for": f"baker{n}"} for n in range(args.number_of_bakers)],
        "regular": [{} for n in range(args.number_of_nodes)],
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

    with open(f"{files_path}_values.yaml", "w") as yaml_file:
        yaml.dump(creation_constants, yaml_file)
        print(f"Wrote chain creation constants to {files_path}_values.yaml")
    with open(f"{files_path}_invite_values.yaml", "w") as yaml_file:
        print(f"Wrote chain invitation constants to {files_path}_invite_values.yaml")
        yaml.dump(invitation_constants, yaml_file)


if __name__ == "__main__":
    main()
