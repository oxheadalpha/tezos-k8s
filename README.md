- [Tezos k8s](#tezos-k8s)
  - [Prerequisites](#prerequisites)
  - [Installing prerequisites](#installing-prerequisites)
    - [Mac](#mac)
    - [Arch Linux](#arch-linux)
    - [Other Operating Systems](#other-operating-systems)
  - [Configuring Minikube](#configuring-minikube)
    - [Mac](#mac-1)
    - [Other Operating Systems](#other-operating-systems-1)
  - [Starting Minikube](#starting-minikube)
  - [Tezos k8s Helm Chart](#tezos-k8s-helm-chart)
- [Joining Mainnet](#joining-mainnet)
  - [Spinning Up a Regular Peer Node](#spinning-up-a-regular-peer-node)
- [Creating a Private Blockchain](#creating-a-private-blockchain)
  - [Zerotier](#zerotier)
  - [mkchain](#mkchain)
  - [Start your private chain](#start-your-private-chain)
  - [Adding nodes within the cluster](#adding-nodes-within-the-cluster)
  - [Adding external nodes to the cluster](#adding-external-nodes-to-the-cluster)
    - [On the computer of the joining node](#on-the-computer-of-the-joining-node)
  - [RPC Authentication](#rpc-authentication)
- [Using a custom Tezos build](#using-a-custom-tezos-build)
- [Indexers](#indexers)
- [Notes](#notes)
- [Development](#development)

# Tezos k8s

This README walks you through:

- spinning up Tezos nodes that will join a public chain, e.g. mainnet.
- creating your own Tezos based private blockchain.

Using `minikube`, your nodes will be running in a peer-to-peer network inside of a Kubernetes cluster. With your custom private blockchain, your network will be also running over a Zerotier VPN.

Follow the prerequisites step first. Then you can jump to either [joining mainnet](#joining-mainnet) or [creating a private chain](#creating-a-private-blockchain).

NOTE: You do not need to clone this repository! All necessary components will be installed.

## Prerequisites

- python3 (>=3.7)
- [docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [minikube](https://minikube.sigs.k8s.io/docs/)
- [helm](https://helm.sh/)
- A [ZeroTier](https://www.zerotier.com/) network with api access token

## Installing prerequisites

This section varies depending on OS.

### Mac

- Install [Docker Desktop](https://docs.docker.com/docker-for-mac/install/).

- Start Docker Desktop and follow the setup instructions. Note: You may quit Docker after it has finished setting up. It is not required that Docker Desktop is running for you to run a Tezos chain.

- Install [homebrew](https://brew.sh/):

  ```shell
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  ```

- Install other prerequisites:
  ```shell
  brew install python3 kubectl minikube helm
  ```

### Arch Linux

```shell
pacman -Syu && pacman -S docker python3 minikube kubectl kubectx helm
```

### Other Operating Systems

Please see the respective pages for installation instructions:

- [python3](https://www.python.org/downloads/)
- [docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [helm](https://helm.sh/docs/intro/install/)

## Configuring Minikube

It is suggested to deploy minikube as a virtual machine. This requires a virtual machine [driver](https://minikube.sigs.k8s.io/docs/drivers/).

### Mac

Requires the [hyperkit](https://minikube.sigs.k8s.io/docs/drivers/hyperkit/) driver. This comes already bundled together with Docker Desktop.

Make hyperkit the default minikube driver:

```shell
minikube config set driver hyperkit
```

(Note: We do not use Docker itself as the minikube driver due to an [issue](https://github.com/kubernetes/minikube/issues/7332) regarding the minikube ingress addon that is required by [rpc-auth](./rpc-auth/README.md))

### Other Operating Systems

If in the next step minikube does not start correctly, you may need to configure a different driver for it. Please see the minikube docs [here](https://minikube.sigs.k8s.io/docs/drivers/) for more information.

## Starting Minikube

```shell
minikube start
```

Configure your shell environment to use minikube’s Docker daemon:

```shell
eval $(minikube docker-env)
```

This allows you to run Docker commands inside of minikube. For example: `docker images` to view the images that minikube has.

If you want to unset your shell from using minikube's docker daemon:

```shell
eval $(minikube docker-env -u)
```

## Tezos k8s Helm Chart

To add the Tezos k8s Helm chart to your local Helm chart repo, run:

```shell
helm repo add oxheadalpha https://oxheadalpha.github.io/tezos-helm-charts/
```

# Development

Please see [DEVELOPMENT.md](./DEVELOPMENT.md)
