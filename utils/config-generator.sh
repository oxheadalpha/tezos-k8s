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

cat > /etc/tezos/tezedge.conf <<EOM
--network=sandbox
--p2p-port=9732
--rpc-port=8732
--websocket-address=0.0.0.0:4927
--init-sapling-spend-params-file=/sapling-spend.params
--init-sapling-output-params-file=/sapling-output.params
--tezos-data-dir=/var/tezos/node/data
--bootstrap-db-path=/var/tezos/node/bootstrap

--bootstrap-lookup-address=tezos-baking-node-0.tezos-baking-node

--sandbox-patch-context-json-file=/etc/tezos/genesis.json
--identity-file=/tmp/tezedge/identity.json
--identity-expected-pow=0
--log-format=simple
--log-level=info
--ocaml-log-enabled=false
--peer-thresh-low=10
--peer-thresh-high=15
--protocol-runner=/protocol-runner
--ffi-pool-max-connections=10
--ffi-trpap-pool-max-connections=10
--ffi-twcap-pool-max-connections=10
--ffi-pool-connection-timeout-in-secs=60
--ffi-trpap-pool-connection-timeout-in-secs=60
--ffi-twcap-pool-connection-timeout-in-secs=60
--ffi-pool-max-lifetime-in-secs=21600
--ffi-trpap-pool-max-lifetime-in-secs=21600
--ffi-twcap-pool-max-lifetime-in-secs=21600
--ffi-pool-idle-timeout-in-secs=1800
--ffi-trpap-pool-idle-timeout-in-secs=1800
--ffi-twcap-pool-idle-timeout-in-secs=1800
--actions-store-backend=rocksdb
--compute-context-action-tree-hashes=false
--tokio-threads=0
--enable-testchain=false
EOM

cat > /etc/tezos/genesis.json <<EOM
{
  "genesis_pubkey": "BKn8byUN52nWQH5ETTudWM62WzAtuz2pkKBXf2eN8XrjtmkEUyt"
}
EOM

#
# Next we write the current baker ccount into /etc/tezos/baking-account.
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
