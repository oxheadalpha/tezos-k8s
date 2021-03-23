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

# charts/tezos/templates/baker.yaml
BAKER_NODE_NAME = "tezos-baking-node"
BAKER_NODE_TYPE = "baking"
# charts/tezos/templates/node.yaml
REGULAR_NODE_NAME = "tezos-node"
REGULAR_NODE_TYPE = "regular"


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


def get_genesis_vanity_chain_id(docker_image, seed_len=16):
    print("Generating vanity chain id")
    seed = "".join(
        random.choice(string.ascii_uppercase + string.digits) for _ in range(seed_len)
    )

    return (
        run_docker(
            docker_image,
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


cli_args = {
    "should_generate_unsafe_deterministic_data": {
        "help": (
            "Should tezos-k8s generate deterministic account keys and genesis"
            " block hash instead of mkchain using tezos-client to generate"
            " random ones. This option is helpful for testing purposes."
        ),
        "action": "store_true",
        "default": False,
    },
    "number_of_nodes": {
        "help": "number of peers in the cluster",
        "default": 0,
        "type": int,
    },
    "number_of_bakers": {
        "help": "number of bakers in the cluster",
        "default": 1,
        "type": int,
    },
    "zerotier_network": {"help": "Zerotier network id for external chain access"},
    "zerotier_token": {"help": "Zerotier token for external chain access"},
    "expected_proof_of_work": {
        "help": "Node identity generation difficulty",
        "default": 0,
        "type": int,
    },
    "bootstrap_peers": {
        "help": "Bootstrap addresses to connect to. Can specify multiple.",
        "action": "extend",
        "nargs": "+",
    },
    "tezos_docker_image": {
        "help": "Version of the Tezos docker image",
        "default": "tezos/tezos:v8-release",
    },
    "rpc_auth": {
        "help": "Should spin up an RPC authentication server",
        "action": "store_true",
        "default": False,
    },
}

# python versions < 3.8 doesn't have "extend" action
class ExtendAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        items = getattr(namespace, self.dest) or []
        items.extend(values)
        setattr(namespace, self.dest, items)


def get_args():
    parser = argparse.ArgumentParser(
        description="Generate helm values for use with the tezos-chain helm chart"
    )

    parser.register("action", "extend", ExtendAction)
    parser.add_argument("chain_name", action="store", help="Name of your chain")
    parser.add_argument(
        "-v",
        "--version",
        action="version",
        version="%(prog)s {version}".format(version=__version__),
    )

    for k, v in cli_args.items():
        parser.add_argument(*["--" + k.replace("_", "-")], **v)

    return parser.parse_args()


def pull_docker_images(images):
    for image in images:
        has_image_return_code = subprocess.run(
            f"docker inspect --type=image {image} > /dev/null 2>&1", shell=True
        ).returncode
        if has_image_return_code != 0:
            print(f"Pulling docker image {image}")
            subprocess.check_output(
                f"docker pull {image}", shell=True, stderr=subprocess.STDOUT
            )
            print(f"Done pulling docker image {image}")


def validate_args(args):
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

    if (not args.zerotier_network and args.zerotier_token) or (
        not args.zerotier_token and args.zerotier_network
    ):
        print("Configuring Zerotier requires both a network id and access token.")
        exit(1)

    if args.zerotier_network and args.should_generate_unsafe_deterministic_data:
        print(
            "Configuring a Zerotier network and generating unsafe deterministic data is not allowed."
        )
        exit(1)


def main():
    args = get_args()

    validate_args(args)

    # Dirty fix. If tezos image doesn't exist, pull it before `docker run` can
    # pull it. This is to avoid parsing extra output. Preferably, we want to get
    # rid of docker dependency from mkchain.
    FLEXTESA = "registry.gitlab.com/tezos/flextesa:01e3f596-run"
    images = [args.tezos_docker_image]
    if not args.should_generate_unsafe_deterministic_data:
        images.append(FLEXTESA)
    pull_docker_images(images)

    base_constants = {
        "images": {
            "tezos": args.tezos_docker_image,
        },
        "node_config_network": {"chain_name": args.chain_name},
        "zerotier_config": {
            "zerotier_network": args.zerotier_network,
            "zerotier_token": args.zerotier_token,
        },
        # Custom chains should not pull snapshots
        "full_snapshot_url": None,
        "rolling_snapshot_url": None,
        "rpc_auth": args.rpc_auth,
    }

    # preserve pre-existing values, if any (in case of scale-up)
    old_create_values = {}
    old_invite_values = {}
    files_path = f"{os.getcwd()}/{args.chain_name}"
    if os.path.isfile(f"{files_path}_values.yaml"):
        print(
            "Found old values file. Some pre-existing values might remain the "
            "same, e.g. public/private keys, and genesis block. Please delete the "
            "values file to generate all new values.\n"
        )
        with open(f"{files_path}_values.yaml", "r") as yaml_file:
            old_create_values = yaml.safe_load(yaml_file)

        current_number_of_bakers = len(old_create_values["nodes"][BAKER_NODE_TYPE])
        if current_number_of_bakers != args.number_of_bakers:
            print("ERROR: the number of bakers must not change on a pre-existing chain")
            print(f"Current number of bakers: {current_number_of_bakers}")
            print(f"Attempted change to {args.number_of_bakers} bakers")
            exit(1)

        if os.path.isfile(f"{files_path}_invite_values.yaml"):
            with open(f"{files_path}_invite_values.yaml", "r") as yaml_file:
                old_invite_values = yaml.safe_load(yaml_file)

    if old_create_values.get("node_config_network", {}).get("genesis"):
        print("Using existing genesis parameters")
        base_constants["node_config_network"]["genesis"] = old_create_values[
            "node_config_network"
        ]["genesis"]
    else:
        # create new chain genesis params if brand new chain
        base_constants["node_config_network"]["genesis"] = {
            "block": get_genesis_vanity_chain_id(FLEXTESA)
            if not args.should_generate_unsafe_deterministic_data
            else "YOUR_GENESIS_BLOCK_HASH_HERE",
            "protocol": "PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex",
            "timestamp": datetime.utcnow().replace(tzinfo=timezone.utc).isoformat(),
        }

    accounts = {"secret": {}, "public": {}}
    if old_create_values.get("accounts"):
        print("Using existing secret keys")
        accounts["secret"] = old_create_values["accounts"]
        if old_invite_values.get("accounts"):
            print("Using existing public keys")
            accounts["public"] = old_invite_values["accounts"]
    elif not args.should_generate_unsafe_deterministic_data:
        baking_accounts = {f"baker{n}": {} for n in range(args.number_of_bakers)}
        for account in baking_accounts:
            print(f"Generating keys for account {account}")
            keys = gen_key(args.tezos_docker_image)
            for key_type in keys:
                accounts[key_type][account] = {
                    "key": keys[key_type],
                    "type": key_type,
                    "is_bootstrap_baker_account": True,
                    "bootstrap_balance": "4000000000000",
                }

    # First 2 bakers are acting as bootstrap nodes for the others, and run in
    # archive mode. Any other bakers will be in rolling mode.
    regular_node_config = {"config": {"shell": {"history_mode": "rolling"}}}
    creation_nodes = {
        BAKER_NODE_TYPE: {
            f"{BAKER_NODE_NAME}-{n}": {
                "bake_using_account": f"baker{n}",
                "is_bootstrap_node": n < 2,
                "config": {
                    "shell": {"history_mode": "archive" if n < 2 else "rolling"}
                },
            }
            for n in range(args.number_of_bakers)
        },
        REGULAR_NODE_TYPE: None,
    }
    if args.number_of_nodes:
        creation_nodes[REGULAR_NODE_TYPE] = {
            f"{REGULAR_NODE_NAME}-{n}": regular_node_config
            for n in range(args.number_of_nodes)
        }

    first_baker_node_name = next(iter(creation_nodes[BAKER_NODE_TYPE]))
    activation_account_name = creation_nodes[BAKER_NODE_TYPE][first_baker_node_name][
        "bake_using_account"
    ]
    base_constants["node_config_network"][
        "activation_account_name"
    ] = activation_account_name

    with open(
        f"{os.path.dirname(os.path.realpath(__file__))}/parameters.yaml", "r"
    ) as yaml_file:
        parametersYaml = yaml.safe_load(yaml_file)
        activation = {
            "activation": {
                "protocol_hash": "PtEdo2ZkT9oKpimTah6x2embF25oss54njMuPzkJTEi5RqfdZFA",
                "should_include_commitments": False,
                "protocol_parameters": parametersYaml,
            },
        }

    bootstrap_peers = args.bootstrap_peers if args.bootstrap_peers else []

    creation_constants = {
        "is_invitation": False,
        "should_generate_unsafe_deterministic_data": args.should_generate_unsafe_deterministic_data,
        "expected_proof_of_work": args.expected_proof_of_work,
        **base_constants,
        "bootstrap_peers": bootstrap_peers,
        "accounts": accounts["secret"],
        "nodes": creation_nodes,
        **activation,
    }

    with open(f"{files_path}_values.yaml", "w") as yaml_file:
        yaml.dump(creation_constants, yaml_file)
        print(f"Wrote chain creation constants to {files_path}_values.yaml")

    # If there is a Zerotier configuration, create an invite file.
    if not args.should_generate_unsafe_deterministic_data and base_constants.get(
        "zerotier_config", {}
    ).get("zerotier_network"):
        invite_nodes = {
            REGULAR_NODE_TYPE: {f"{REGULAR_NODE_NAME}-0": regular_node_config},
            BAKER_NODE_TYPE: {},
        }
        invitation_constants = {
            "is_invitation": True,
            "expected_proof_of_work": args.expected_proof_of_work,
            **base_constants,
            "accounts": accounts["public"],
            "bootstrap_peers": bootstrap_peers,
            "nodes": invite_nodes,
        }
        invitation_constants.pop("rpc_auth")

        with open(f"{files_path}_invite_values.yaml", "w") as yaml_file:
            print(
                f"Wrote chain invitation constants to {files_path}_invite_values.yaml"
            )
            yaml.dump(invitation_constants, yaml_file)


if __name__ == "__main__":
    main()
