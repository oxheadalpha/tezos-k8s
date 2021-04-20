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

- python3 (>=3.6)
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
helm repo add tqtezos https://tqtezos.github.io/tezos-helm-charts
```

# Joining Mainnet

## Spinning Up a Regular Peer Node

Connecting to a public net is easy!

(See [here](https://tezos.gitlab.io/user/history_modes.html) for info on snapshots and node history modes)

If you'd like to spin up a node that runs with history mode rolling, all you need to do is run:

```shell
helm install tezos-mainnet tqtezos/tezos-chain \
--namespace tqtezos --create-namespace
```

If you'd like to spin up a node with history mode full, run:

```shell
helm install tezos-mainnet tqtezos/tezos-chain \
--namespace tqtezos --create-namespace \
--set nodes.regular.tezos-node-0.config.shell.history_mode=full
```

Running either of these commands results in:

- Creating a Helm [release](https://helm.sh/docs/intro/using_helm/#three-big-concepts) named tezos-mainnet in your k8s cluster.
- k8s will spin up one regular (i.e. non-baking node) which will download and import a mainnet snapshot. This will take a few minutes.
- Once the snapshot step is done, your node will be bootstrapped and syncing with mainnet!

You can find your node in the tqtezos namespace with some status information using `kubectl`.

```shell
kubectl -n tqtezos get pods -l appType=tezos-node
```

You can monitor (and follow using the `-f` flag) the logs of the snapshot downloader/import container:

```shell
kubectl logs -n tqtezos statefulset/tezos-node -c snapshot-downloader -f
```

You can view logs for your node using the following command:

```shell
kubectl -n tqtezos logs -l appType=tezos-node -c tezos-node -f --prefix
```

IMPORTANT:

- Although spinning up a mainnet baker is possible, we do not recommend running a mainnet baker at this point in time. Secret keys should be handled via an HSM that should remain online, and the keys should be passed through a k8s secret to k8s. This functionality still needs to be implemented.
- You should be aware of `minikube` VM's allocated memory. Especially if you use `minikube` for other applications. It may run out of virtual memory say due to having large docker images. Being that snapshots are relatively large and increasing in size as the blockchain grows, when downloading one, you can potentially run out of disk space. The snapshot is deleted after import. According to `minikube start --help`, default allocated space is 20000mb. You can modify this via the `--disk-size` flag. To view the memory usage of the VM, you can ssh into `minikube`.

  ```shell
  ❯ minikube ssh
                          _             _
              _         _ ( )           ( )
    ___ ___  (_)  ___  (_)| |/')  _   _ | |_      __
  /' _ ` _ `\| |/' _ `\| || , <  ( ) ( )| '_`\  /'__`\
  | ( ) ( ) || || ( ) || || |\`\ | (_) || |_) )(  ___/
  (_) (_) (_)(_)(_) (_)(_)(_) (_)`\___/'(_,__/'`\____)

  $ df -h
  Filesystem      Size  Used Avail Use% Mounted on
  tmpfs           5.2G  593M  4.6G  12% /
  devtmpfs        2.8G     0  2.8G   0% /dev
  tmpfs           2.9G     0  2.9G   0% /dev/shm
  tmpfs           2.9G   50M  2.8G   2% /run
  tmpfs           2.9G     0  2.9G   0% /sys/fs/cgroup
  tmpfs           2.9G  8.0K  2.9G   1% /tmp
  /dev/vda1        17G   12G  4.2G  74% /mnt/vda1
  ```

# Creating a Private Blockchain

## Zerotier

Zerotier is a VPN service that the Tezos nodes in your cluster will use to communicate with each other.

Create a ZeroTier network:

- Go to https://my.zerotier.com
- Login with credentials or create a new account
- Go to https://my.zerotier.com/account to create a new API access token
- Under `API Access Tokens > New Token`, give a name to your access token and generate it by clicking on the "generate" button. Save the generated access token, e.g. `yEflQt726fjXuSUyQ73WqXvAFoijXkLt` on your computer.
- Go to https://my.zerotier.com/network
- Create a new network by clicking on the "Create a Network"
  button. Save the 16 character generated network
  id, e.g. `1c33c1ced02a5eee` on your computer.

Set Zerotier environment variables in order to access the network id and access token values with later commands:

```shell
export ZT_TOKEN=yEflQt726fjXuSUyQ73WqXvAFoijXkLt
export ZT_NET=1c33c1ced02a5eee
```

## mkchain

mkchain is a python script that generates Helm values, which Helm then uses to create your Tezos chain on k8s.

Follow _just_ the [Install mkchain](./mkchain/README.md#install-mkchain) step in `./mkchain/README.md`. See there for more info on how you can customize your chain.

Set as an environment variable the name you would like to give to your chain:

```shell
export CHAIN_NAME=my-chain
```

NOTE: k8s will throw an error when deploying if your chain name format does not match certain requirements. From k8s: `DNS-1123 subdomain must consist of lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character (e.g. 'example.com', regex used for validation is '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*')`

Set [unbuffered IO](https://docs.python.org/3.6/using/cmdline.html#envvar-PYTHONUNBUFFERED) for python:

```shell
export PYTHONUNBUFFERED=x
```

## Start your private chain

Run `mkchain` to create your Helm values

```shell
mkchain $CHAIN_NAME --zerotier-network $ZT_NET --zerotier-token $ZT_TOKEN
```

This will create two files:

1. `./${CHAIN_NAME}_values.yaml`
2. `./${CHAIN_NAME}_invite_values.yaml`

The former is what you will use to create your chain, and the latter is for invitees to join your chain.

Create a Helm release that will start your chain:

```shell
helm install $CHAIN_NAME tqtezos/tezos-chain \
--values ./${CHAIN_NAME}_values.yaml \
--namespace tqtezos --create-namespace
```

Your kubernetes cluster will now be running a series of jobs to
perform the following tasks:

- get a zerotier ip
- generate a node identity
- create a baker account
- generate a genesis block for your chain
- start the bootstrap-node baker to bake/validate the chain
- activate the protocol
- bake the first block

You can find your node in the tqtezos namespace with some status information using kubectl.

```shell
kubectl -n tqtezos get pods -l appType=tezos-node
```

You can view (and follow using the `-f` flag) logs for your node using the following command:

```shell
kubectl -n tqtezos logs -l appType=tezos-node -c tezos-node -f --prefix
```

Congratulations! You now have an operational Tezos based permissioned
chain running one node.

## Adding nodes within the cluster

You can spin up a number of regular peer nodes that don't bake in your cluster by passing `--number-of-nodes N` to `mkchain`. Pass this along with your previously used flags (`--zerotier-network` and `--zerotier-token`). You can use this to both scale up and down.

Or if you previously spun up the chain using `mkchain`, you may scale up/down your setup to an arbitrary number of nodes by adding or removing nodes in the `nodes.regular` list in the values yaml file:

```yaml
# <CURRENT WORKING DIRECTORY>/${CHAIN_NAME}_values.yaml
nodes:
  regular:
    tezos-node-0: # first non-baking node
      config:
        shell:
          history_mode: rolling
    tezos-node-1: # second non-baking node
      config:
        shell:
          history_mode: rolling
```

IMPORTANT: If you are manually editing the values yaml file, you must make sure that the names of the nodes follow this format: `tezos-node-N`, where `N` is an integer referring to the index of the node. So the first node is `tezos-node-0`, the second `tezos-node-1`, etc.

To upgrade your Helm release run:

```shell
helm upgrade $CHAIN_NAME tqtezos/tezos-chain \
--values ./${CHAIN_NAME}_values.yaml \
--namespace tqtezos
```

The nodes will start up and establish peer-to-peer connections in a full mesh topology.

List all of your running nodes: `kubectl -n tqtezos get pods -l appType=tezos-node`

## Adding external nodes to the cluster

External nodes to your local cluster can be added to your network by sharing a yaml file
generated by the `mkchain` command.

The file is located at: `<CURRENT WORKING DIRECTORY>/${CHAIN_NAME}_invite_values.yaml`

Send this file to the recipients you want to invite.

### On the computer of the joining node

The member needs to:

1. Follow the [prerequisite installation instructions](#installing-prerequisites)
2. [Start minikube](#start-minikube)

Then run:

```shell
helm repo add tqtezos https://tqtezos.github.io/tezos-helm-charts

helm install $CHAIN_NAME tqtezos/tezos-chain \
--values <LOCATION OF ${CHAIN_NAME}_invite_values.yaml> \
--namespace tqtezos --create-namespace
```

At this point additional nodes will be added in a full mesh
topology.

Congratulations! You now have a multi-node Tezos based permissioned chain.

On each computer, run this command to check that the nodes have matching heads by comparing their hashes (it may take a minute for the nodes to sync up):

```shell
kubectl get pod -n tqtezos -l appType=tezos-node -o name |
while read line;
  do kubectl -n tqtezos exec $line -c tezos-node -- /usr/local/bin/tezos-client rpc get /chains/main/blocks/head/hash;
done
```

## RPC Authentication

You can optionally spin up an RPC authentication backend allowing trusted users to make RPC requests to your cluster.

Follow the steps [here](./rpc-auth/README.md).

# Notes

- We recommend using a very nice GUI for your k8s Tezos chain infrastructure called [Lens](https://k8slens.dev/). This allows you to easily see all of the k8s resources that have been spun up as well as to view the logs for your Tezos nodes.

# Development

Please see [DEVELOPMENT.md](./DEVELOPMENT.md)
