#!/bin/bash

set -x

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"

proto_command=$(echo $CHAIN_PARAMS | jq -r '.proto_command')
if [ "${DAEMON}" == "baker" ]; then
    extra_args="with local node $NODE_DIR"
fi
POD_INDEX=$(echo $POD_NAME | sed -e s/tezos-baking-node-//)
baker_account=$(echo $NODES | jq -r ".baking[${POD_INDEX}].bake_for")

if [ "$baker_account" = null ]; then
    baker_account="baker$POD_INDEX"
fi

CLIENT="$TEZ_BIN/tezos-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/tezos-$DAEMON-$proto_command -d $CLIENT_DIR"

#
# All bakers need to wait for their local node to be bootstrapped:

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

#
# And, obviously, we need to actually bake:

$CMD run ${extra_args} ${baker_account}
