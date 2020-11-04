from __future__ import annotations

import argparse
import base64
import os
import random
import shutil
import string
import subprocess
import sys
import uuid

import dhall  # type: ignore
import yaml

from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Union

from kubernetes import client as k8s_client
from kubernetes import config as k8s_config

my_path = os.path.dirname(os.path.abspath(__file__))


def run_docker(image: str, entrypoint: str, *args: str) -> bytes:
    return subprocess.check_output(
        "docker run --entrypoint %s --rm %s %s" % (entrypoint, image, " ".join(args)),
        stderr=subprocess.STDOUT,
        shell=True,
    )


def gen_key(image: str) -> dict[str, str]:
    keys = run_docker(
        image,
        "sh",
        "-c",
        "'/usr/local/bin/tezos-client --protocol PsCARTHAGazK gen keys mykey && /usr/local/bin/tezos-client --protocol PsCARTHAGazK show address mykey -S'",
    ).split(b"\n")

    def extract_key(index: int) -> str:
        return base64.b64encode(
            keys[index].split(b":")[index].strip().decode("utf-8").encode("ascii")
        ).decode()

    return {"public_key": extract_key(1), "secret_key": extract_key(2)}


def get_genesis_vanity_chain_id(seed_len: int = 16) -> str:
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
        "default": 4000000000000,
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


def get_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Deploys a private Tezos chain on Kuberenetes"
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
    parser.add_argument(
        "--cluster",
        default="minikube",
        help="kubernetes cluster type (minikube, eks...)",
    )

    return parser.parse_args()


def toMap(obj: dict[Any, Any]) -> list[dict[Any, Any]]:
    """
    Python dict to dhall heterogeneous map
    """
    return [{"mapKey": k, "mapValue": v} for k, v in obj.items()]


def remove_nones(xs: Union[list[Any], dict[Any, Any], Any]) -> Any:
    """
    Recursively removes none values from lists and dicts
    """
    if isinstance(xs, dict):
        return {k: remove_nones(v) for k, v in xs.items() if v is not None}
    elif isinstance(xs, list):
        return [remove_nones(x) for x in xs if x is not None]
    else:
        return xs


dhall_query = """
let mkchain = {script_path}/dhall/mkchain.dhall

in  mkchain.{action} ({dhall_config_file} // {overrides})
"""


def main() -> None:
    args = get_args()
    bootstrap_accounts = [
        "baker",
        "bootstrap_account_1",
        "bootstrap_account_2",
        "genesis",
    ]

    if args.action == "generate-constants":
        zt_hostname = str(uuid.uuid4())
        print(f"zt_hostname: {zt_hostname}", file=sys.stderr)
        zerotier_enabled = bool(args.zerotier_network and args.zerotier_token)

        base_constants = {
            "genesis_chain_id": get_genesis_vanity_chain_id(),
            "bootstrap_timestamp": datetime.utcnow()
            .replace(tzinfo=timezone.utc)
            .isoformat(),
            "bootstrap_peer": "tezos-bootstrap-node-p2p:9732",
            "chain_name": args.chain_name,
            "bootstrap_accounts": base64.b64encode(
                " ".join(bootstrap_accounts).encode("ascii")
            ).decode(),
            "zerotier_enabled": zerotier_enabled,
            "zerotier_data": toMap({"ZTHOSTNAME": zt_hostname}),
        }

        for k in CHAIN_CONSTANTS.keys():
            if (not k.startswith("zerotier")) and vars(args)[k] is not None:
                base_constants[k] = vars(args)[k]

        if zerotier_enabled:
            base_constants["zerotier_data"] += toMap(
                {
                    "NETWORK_IDS": args.zerotier_network,
                    "ZTAUTHTOKEN": args.zerotier_token,
                }
            )

        secret_keys = {}
        public_keys = {}
        for account in bootstrap_accounts:
            keys = gen_key(args.docker_image)
            secret_keys[f"{account}_secret_key"] = keys["secret_key"]
            public_keys[f"{account}_public_key"] = keys["public_key"]

        creation_constants = {**base_constants, "keys": toMap(secret_keys)}
        invitation_constants = {**base_constants, "keys": toMap(public_keys)}

        with open(f"{args.chain_name}_chain.dhall", "w") as dhall_file:
            dhall.dump(creation_constants, dhall_file)
            print(f"Wrote create constants in {args.chain_name}_chain.dhall")
        with open(f"{args.chain_name}_chain_invite.dhall", "w") as dhall_file:
            print(f"Wrote invitation constants in {args.chain_name}_chain_invite.dhall")
            dhall.dump(invitation_constants, dhall_file)
        exit(0)

    overrides = {k: v for k, v in vars(args).items() if k in CHAIN_CONSTANTS and v}

    if args.action == "create":
        config_file = Path(f"{args.chain_name}_chain.dhall")
    elif args.action == "invite":
        config_file = Path(f"{args.chain_name}_chain_invite.dhall")
        try:
            k8s_config.load_kube_config()
            v1 = k8s_client.CoreV1Api()
        except TypeError:
            print(
                "It looks like you don't have any reachable kubernetes instances.\nInvitation can only be generated with a running k8s chain.",
                file=sys.stderr,
            )
            exit(1)
        bootstrap_peer = args.bootstrap_peer
        if not bootstrap_peer:
            print(f"--bootstrap-peer argument is required for invite", file=sys.stderr)
            exit(1)
        node_port = (
            v1.read_namespaced_service("tezos-bootstrap-node-p2p", "tqtezos")
            .spec.ports[0]  # type: ignore
            .node_port
        )
        overrides["bootstrap_peer"] = f"{bootstrap_peer}:{node_port}"
    else:
        exit(1)

    if not config_file.exists():
        print(
            f"Could not find the constants file {config_file}, did you run mkchain generate-constants <chain_name> ?",
            file=sys.stderr,
        )
        exit(1)

    query = dhall_query.format(
        action=args.action,
        dhall_config_file=str(config_file.absolute()),
        overrides=dhall.dumps(overrides),
        script_path=my_path,
    )

    # the binary is a lot more performant so use it when available
    dhall_bin = shutil.which("dhall-to-yaml")
    if False:
        dhall_run = subprocess.run(
            [dhall_bin, "--documents"], input=query.encode(), capture_output=True
        )
        print(dhall_run.stderr.decode(), file=sys.stderr)
        print(dhall_run.stdout.decode(), file=sys.stdout)
        exit(dhall_run.returncode)
    else:
        print(
            "It looks like you don't have a `dhall-to-yaml` binary in your $PATH.\nConsider installing dhall for faster mkchain runs: https://github.com/dhall-lang/dhall-lang",
            file=sys.stderr,
        )
        output = dhall.loads(query)
        yaml.dump_all(remove_nones(output), sys.stdout)  # type: ignore
