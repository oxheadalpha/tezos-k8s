#!/bin/sh
mkdir -p /var/tezos/client
chmod -R 777 /var/tezos/client

for acct in ${BOOTSTRAP_ACCOUNTS}; do
    key=$(eval echo \$${acct}_${KEYS_TYPE}_key)
    tezos-client -d /var/tezos/client --protocol PsCARTHAGazK import ${KEYS_TYPE} key $acct unencrypted:${key} -f
done
