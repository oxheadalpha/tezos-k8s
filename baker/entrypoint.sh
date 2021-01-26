#!/bin/bash

set -x

baker_command=$(echo $CHAIN_PARAMS | jq -r '.baker_command')
POD_INDEX=$(echo $POD_NAME | sed -e s/tezos-baking-node-//)
acct=$(echo $NODES | jq -r ".baking[${POD_INDEX}].bake_for")

CLIENT_DIR=/var/tezos/client
CLIENT="/usr/local/bin/tezos-client -d $CLIENT_DIR"
BAKER="/usr/local/bin/$baker_command -d $CLIENT_DIR"

if [ -z "$acct" ]; then
    echo Baker account not set 1>&2
    exit 1
fi

#
# All bakers need to wait for their local node to be bootstrapped:

while ! $CLIENT bootstrapped; do
    sleep 5
done

#
# Non-genesis bakers need to setup their accounts so that they can bake:

if [ "$acct" != baker0 ]; then
    ZBALANCE="$($CLIENT get balance for baker0)"
    BALANCE="$($CLIENT get balance for $acct)"

    ZBALANCE="${ZBALANCE%%[^0-9]*}"
    BALANCE="${BALANCE%%[^0-9]*}"

    TARGET="$(echo "($ZBALANCE - 100000) / 2 ^ $POD_INDEX" | bc)"
    ADD="$(echo $TARGET - $BALANCE | bc)"

    if [ "$ADD" -gt 0 ]; then
	while ! $CLIENT transfer $ADD from baker0 to $acct --burn-cap 100; do
		sleep 10
	done
    fi

fi

#
# And, obviously, we need to actually bake:

$BAKER run with local node /var/tezos/node $acct
