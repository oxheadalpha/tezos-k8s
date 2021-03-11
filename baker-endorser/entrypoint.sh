#!/bin/bash

set -x

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

proto_command=$(echo $CHAIN_PARAMS | jq -r '.proto_command')
if [ "${DAEMON}" == "baker" ]; then
    extra_args="with local node $NODE_DATA_DIR"
fi

my_baker_account=$(echo $NODES | jq -r ".${MY_NODE_TYPE}.\"${MY_POD_NAME}\".bake_using_account")
# If not account to bake for was specified in the node's settings,
# config-generator defaults the account name to the pod's name.
if [ "$my_baker_account" = null ]; then
    my_baker_account="$MY_POD_NAME"
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

$CMD run ${extra_args} ${my_baker_account}
