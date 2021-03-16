#!/bin/sh

set -ex

tezos_network=$(echo $CHAIN_PARAMS | jq -r 'if (.network | type=="string") then .network else empty end')
chain_type=$(echo $CHAIN_PARAMS | jq -r '.chain_type')

if [ "${chain_type}" == "public" ]; then
    if [ -z "$tezos_network" ]; then
      echo "ERROR: No network given"
      exit 1
    fi

    printf "Writing custom configuration for public node\n"
    mkdir -p /tmp/data

    # We use this command to extract the data we need from the binary
    # for the python script below.
    /usr/local/bin/tezos-node config init \
        --config-file /tmp/data/config.json \
        --data-dir /tmp/data \
        --network $tezos_network

    cat /tmp/data/config.json
    echo ""

fi

sudo mkdir -p /var/tezos/client
sudo chmod -R 777 /var/tezos/client
python3 /entrypoint.py $@

if [ "${chain_type}" == "public" ]; then
    rm -r /tmp/data/
fi
