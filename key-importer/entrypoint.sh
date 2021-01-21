#!/bin/sh

mkdir -p /var/tezos/client
chmod -R 777 /var/tezos/client

PROTOCOL=$(echo $CHAIN_PARAMS | jq -r '.protocol_hash')

import_single_key() {
    read keytype
    read name
    read key

echo tezos-client -d /var/tezos/client --protocol $PROTOCOL \
	import ${keytype} key ${name} unencrypted:${key} -f

    tezos-client -d /var/tezos/client --protocol $PROTOCOL \
	import ${keytype} key ${name} unencrypted:${key} -f
    echo "Imported keytype $keytype name $name"
}

import_all_keys() {
    echo $ACCOUNTS | jq -c --raw-output .[] | while read LINE; do
	echo $LINE | jq -r '.type, .name, .key' | import_single_key
    done
}

import_key() {
    echo $ACCOUNTS | \
    jq -r ".[] | select(.name == \"baker$1\") | .type, .name, .key" | 
	import_single_key
}

HOSTNAME=$(hostname)
MY_NODE=${HOSTNAME##tezos-baking-node-}

#
# The activation job needs all of the keys:

if [ "${HOSTNAME#activate-job}" != ${HOSTNAME} ]; then
    import_all_keys
    exit 0
fi

#
# For some reason, we all need to have baker0's key.  We can likely
# fix this in the future, I would imagine.

import_key 0

if [ "$MY_NODE" != "$HOSTNAME" -a "$MY_NODE" != 0 ]; then
    import_key $MY_NODE
fi
