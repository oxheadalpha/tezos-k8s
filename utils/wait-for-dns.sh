#!/bin/sh

# When the octez-node boots for the first time, if one of the bootstrap
# nodes can't be contacted, then octez-node will give up.
# So at first boot (when peers.json is empty) we wait for bootstrap node.
# This is probably a bug in tezos core, though.

if [ -s /var/tezos/node/peers.json ] && [ "$(jq length /var/tezos/node/peers.json)" -gt "0" ]; then
    printf "Node already has an internal list of peers, no need to wait for bootstrap \n"
    exit 0
fi

PRIVATE_NET=$(echo $CHAIN_PARAMS | jq -r '.network.genesis')

if [ "$PRIVATE_NET" = null ]; then
    echo "We are not setting up a private network, it is not necessary"
    echo "to wait for the bootstrap nodes as they are likely external."
    exit 0
fi

#
# BOOTSTRAP_PEERS will be a space separated list of all of the bootstrap
# nodes.  We use jq to extract this list from /etc/tezos/config.json because
# the data structure is much simpler than what we find in $NODES.

BOOTSTRAP_PEERS=$(< /etc/tezos/config.json jq -r	\
	'.p2p."bootstrap-peers"[]|split(":")[0]')

for peer in $BOOTSTRAP_PEERS; do
    while ! getent hosts $peer; do
	echo "Waiting for name service for $peer"
	sleep 5
    done
done
