#!/bin/sh

# When the tezos-node boots for the first time and the bootstrap node is not up yet, it will never connect.
# So at first boot (when peers.json is empty) we wait for bootstrap node.
# This is probably a bug in tezos core, though.

if [ -e /var/tezos/node/peers.json ] && [ "$(jq length /var/tezos/node/peers.json)" -gt "0" ]; then
    printf "Node already has an internal list of peers, no need to wait for bootstrap \n"
    exit 0
fi

FIRST_BOOTSTRAP_NODE="tezos-baking-node-0.tezos-baking-node"
if [ "$(hostname -f | cut -d"." -f1-2)" == "${FIRST_BOOTSTRAP_NODE}" ]; then
    printf "do not wait for myself\n"
    exit 0
fi

# wait for node to respond to rpc
until nc -q 0 ${FIRST_BOOTSTRAP_NODE} 8732; do echo "waiting for bootstrap node to accept connections"; sleep 2; done;
