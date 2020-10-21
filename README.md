# tezos-k8s

helper program to deploy tezos on kubernetes

## quickstart

``` shell
python3 -m venv .venv
source .venv/bin/activate
pip install -e ./
```

## private chain

### Generate constants

Your chain is uniquely defined by a set of values such as bootstrap account keys, chain id, timestamp...

Create these values:

``` shell
mkchain --generate-constants $CHAIN_NAME
```

It will create two 2 yaml files, `<$CHAIN_NAME>_chain.yaml` and `<$CHAIN_NAME>_chain_invite.yaml`.

### create
$CHAIN_NAME: is your private chain's name

``` shell
mkchain --create --baker $CHAIN_NAME | kubectl apply -f -
```

### invite
$CHAIN_NAME: is your private chain's name
$IP is the ip address your node will serve rpc on.

Output is suitable to copy/paste and share with joiners.

``` shell
IP=$(kubectl -n tqtezos exec  daemonsets/zerotier-bridge -- zerotier-cli get $ZT_NET ip)
mkchain --invite --bootstrap-peer $IP $CHAIN_NAME > join-$CHAIN_NAME.yaml
```

### join
You will typically receive a yaml file from a private chain creator.


## EKS
https://aws.amazon.com/premiumsupport/knowledge-center/eks-persistent-storage/
