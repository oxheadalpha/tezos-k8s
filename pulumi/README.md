# Using Pulumi to deploy a private chain in AWS

This README will walk you through setting up a Tezos based private
blockchain where you will spin up many bootstrap nodes as well as additional
peer nodes if you'd like.  We will demonstrate this in AWS EKS (Elastic
Kubernetes Service).

This guide describes how to deploy the cluster as a developer of
this framework.  That is, this is the way to update the framework
that deploys said networks.

We are not using Zerotier in this example.

## Prerequisites

- python3
    - pip
    - python3-venv
- [docker](https://docs.docker.com/get-docker/)
    - make sure that you add your username to the docker group
    - https://docs.docker.com/engine/install/linux-postinstall/
- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [helm](https://helm.sh/)
- AWS CLI
- nodejs
- pulumi
    - install pulumi
    - create and account and tokens
    - pulumi has some modules to install

## mkchain

mkchain is a python script that generates Helm values, which Helm then
uses to create your Tezos chain on k8s.

Follow _just_ the [Install mkchain](./mkchain/README.md#install-mkchain)
step in `./mkchain/README.md`. See there for more info on how you can
customize your chain.  At the moment, this is development code and so
you can't use the mkchain that pip installs by default.  You must rather
do:

```shell
python3 -m venv .venv
. .venv/bin/activate
pip install wheel && pip install ./mkchain
```

at the top level of this git repository.  Note the ./mkchain, this tells
pip to install the version that you have currently checked out.

Set as an environment variable the name you would like to give to your chain:

```shell
export CHAIN_NAME=pulumi
```

We'll assume that you've set that from this point in.

## Helm dependencies

You need to run:

```shell
helm dependency update charts/tezos
```

before we begin and after certain changes to the helm charts.

## Create your chain values files:

Run the following commands to create the helm chart values files.

```shell
mkchain --number-of-bakers 10 $CHAIN_NAME
```

## Use Pulumi to "make it so"

First you must set up a Pulumi "stack".  You can define multiple
stacks and switch between them for deploying different sets of nodes.

```shell
pulumi stack init my_name
```

We look for the values file as `${STACK_NAME}_values.yaml`.

### Configure Pulumi

Pulumi has the ability to set configuration parameters for each stack
that it maintains.  Some of the parameters are generic and some are
specific to tezos-k8s.  It is required to set an AWS region, when
deploying to AWS:

```shell
pulumi config set aws:region us-east-2
```

We also defined a number of parameters for tezos-k8s:

```shell
pulumi config set max-cluster-capacity 100
pulumi config set nodes-per-vm 8
pulumi config set cloudwatch true
pulumi config set rpc-auth true
```

## Actually "make it so" this time

```shell
pulumi up
```

The last command will take quite a long time.  Don't kill it, that
can leave pulumi in a bad state.

## Examine the network that you are creating.

Pulumi will output a `kubeconfig.json` that you can use with your
existing tools to examine the cluster you just created.  You can
have a look at the bakers and nodes via:

```shell
pulumi stack output kubeconfig > /tmp/kubeconfig.json
export KUBECONFIG=/tmp/kubeconfig.json
kubectl -n tezos get pods
```

As long as that works, you should be able to examine the cluster
using `kubectl`, `k9s`, etc.

If things don't come up, or if the behaviour is odd, try:

```shell
kubectl -n tezos describe statefulsets
```
