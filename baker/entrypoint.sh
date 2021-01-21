#!/bin/bash

set -x

baker_command=$(echo $CHAIN_PARAMS | jq -r '.baker_command')
POD_INDEX=$(echo $POD_NAME | sed -e s/tezos-baking-node-//)
baker_account=$(echo $NODES | jq -r ".baking[${POD_INDEX}].bake_for")
/usr/local/bin/${baker_command} -d /var/tezos/client run with local node /var/tezos/node ${baker_account:?Error: baker account not set}
