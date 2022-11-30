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
# Generate the tezedge configuration file:

cat > /etc/tezos/tezedge.conf <<EOM
--network=custom
--custom-network-file=/etc/tezos/config.json
--p2p-port=9732
--rpc-port=8732
--init-sapling-spend-params-file=/sapling-spend.params
--init-sapling-output-params-file=/sapling-output.params
--tezos-data-dir=/var/tezos/node/data
--bootstrap-db-path=/var/tezos/node/bootstrap
--identity-file=/tmp/tezedge/identity.json
--identity-expected-pow=0
--log-format=simple
--log-level=info
--ocaml-log-enabled=false
--peer-thresh-low=10
--peer-thresh-high=15
--protocol-runner=/protocol-runner
--tokio-threads=0
--enable-testchain=false
--log=terminal
EOM

< /etc/tezos/config.json jq -r '.p2p."bootstrap-peers"[]'	| \
	tr '\012' ',' | sed s/^/--bootstrap-lookup-address=/	  \
		>> /etc/tezos/tezedge.conf
