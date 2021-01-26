#!/bin/bash

set -x

proto_command=$(echo $CHAIN_PARAMS | jq -r '.proto_command')
if [ "${WHAT}" == "baker" ]; then
    extra_args="with local node /var/tezos/node"
fi
POD_INDEX=$(echo $POD_NAME | sed -e s/tezos-baking-node-//)
baker_account=$(echo $NODES | jq -r ".baking[${POD_INDEX}].bake_for")
/usr/local/bin/tezos-${WHAT}-${proto_command} -d /var/tezos/client run ${extra_args} ${baker_account:?Error: baker account not set}
