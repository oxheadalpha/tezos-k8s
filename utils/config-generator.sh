#!/bin/sh -x

ls -l /etc/tezos/data
echo ------------------------------------------------------------
cat /etc/tezos/data/config.json
echo ------------------------------------------------------------

mkdir -p /var/tezos/client
chmod -R 777 /var/tezos
set -e
python3 /config-generator.py "$@"
set +e

#
# Next we write the current baker account into /etc/tezos/baking-account.
# We do it here because we shall use jq to process some of the environment
# variables and we are not guaranteed to have jq available on an arbitrary
# tezos docker image.

MY_CLASS=$(echo $NODES | jq -r ".\"${MY_NODE_CLASS}\"")
AM_I_BAKER=$(echo $MY_CLASS | jq -r '.runs|map(select(. == "baker"))|length')

if [ "$AM_I_BAKER" -eq 1 ]; then
    my_baker_account=$(echo $MY_CLASS | \
	    jq -r ".instances[${MY_POD_NAME#$MY_NODE_CLASS-}]
		   .bake_using_account")

    # If no account to bake for was specified in the node's settings,
    # config-generator defaults the account name to the pod's name.
    if [ "$my_baker_account" = null ]; then
	my_baker_account="$MY_POD_NAME"
    fi

    echo "$my_baker_account" > /etc/tezos/baker-account
fi
