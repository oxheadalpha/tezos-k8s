# tezos-k8s

helper program to deploy tezos on kubernetes

## quickstart

``` shell
python3 -m venv .venv
source .venv/bin/activate
pip install -e ./
```

## private chain

### create
$CHAIN_NAME: is your private chain's name
$CLUSTER: one of [minikube, docker-desktop]

``` shell
mkchain --create --stdout --baker $CHAIN_NAME $CLUSTER | kubectl apply -f -
```

### invite
$CHAIN_NAME: is your private chain's name
$IP is the ip address your node will serve rpc on.

Output is suitable to copy/paste and share with joiners.

``` shell
mkchain --invite --bootstrap-peer $IP $CHAIN_NAME
```

### join
You will typically receive this command from a private chain creator.

``` shell
mkchain --stdout --join --genesis-key edpku1b5LnogwYES9feYeiz68Snyzbx1vX96nvz3y6PVwP4LAHr1Rd --timestamp 2020-05-19T01:16:13.192419+00:00 --bootstrap-peer 192.168.10.8:30873 PRIVATE_CHAIN | kubectl apply -f -
```

### vpn
use the following options to join nodes to a zerotier network
$ZT_NETWORKID is the 16 character zerotier network id
$ZT_TOKEN is a zerotier api access token

--zerotier-network $ZT_NETWORKID
--zerotier-token $ZT_TOKEN
