import argparse
import subprocess
import os
import sys
import json

common_templates = ["deployment/tznode.yaml"]
local_templates = []
eks_templates = []

my_path = os.path.abspath(os.path.dirname(__file__))
init_path = os.path.join(my_path, "scripts", "tzinit.sh")
config_path = os.path.join(my_path, "work", "node", "config.json")
parameters_path = os.path.join(my_path, "work", "client", "parameters.json")
tezos_dir = os.path.expanduser("~/.tq/")


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("chain_name")
    parser.add_argument("--tezos-dir", default=tezos_dir)
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--join", help="ip of peer")

    subparsers = parser.add_subparsers(help="targets")

    parser.add_argument("--stdout", action="store_true")
    parser.add_argument(
        "--protocol-hash", default="PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb"
    )
    parser.add_argument(
        "--docker-image", default="tezos/tezos:v7.0-rc1_cde7fbbb_20200416150132"
    )
    parser.add_argument("-c", "--config-file", default=config_path)
    parser.add_argument("-p", "--parameters-file", default=parameters_path)
    parser.add_argument(
        "-e",
        "--extra",
        action="append",
        help="pass additional template values in the form foo=bar",
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


def main():

    args = vars(get_args())
    # assign the contents of config.json to a template variable for the ConfigMap
    args["config_json"] = json.dumps(json.load(open(args["config_file"], "r")))
    args["parameters_json"] = json.dumps(json.load(open(args["parameters_file"], "r")))
    if args["extra"]:
        for extra in args["extra"]:
            arg, val = extra.split("=", 1)
            args[arg] = val

    if args.get("minikube"):
        try:
            minikube_route = subprocess.check_output(
                '''minikube ssh "route -n | grep ^0.0.0.0"''', shell=True
            ).split()
            minkube_gw, minicube_iface = minikube_route[0], minikube_route[7]
            minikube_ip = subprocess.check_output(
                '''minikube ssh "ip addr show eth0|awk /^[[:space:]]+inet/'{print \$2}'"''',
                shell=True,
            ).split("/")[0]
        except subprocess.CalledProcessError as e:
            print("failed to get minikube route %r" % e)

    if args["create"]:
        subprocess.check_output(
            "%s --chain-name %s --work-dir %s"
            % (init_path, args["chain_name"], args["tezos_dir"]),
            shell=True
        )
        args["template"].append("deployment/activate.yaml")

    if args["stdout"]:
        out = sys.stdout
    else:
        out = open("tq-{}.yaml".format(args["chain-name"]), "wb")

    with out as yaml_file:
        for template in args["template"]:
            with open(template) as template_file:
                template = template_file.read()
                out_yaml = template.format(**args)
            yaml_file.write(out_yaml.encode("utf-8"))
            yaml_file.write(b"\n---\n")


if __name__ == "__main__":
    main()
