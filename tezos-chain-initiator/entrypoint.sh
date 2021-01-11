#!/bin/sh

set -x
# wait for node to exist
until nslookup tezos-bootstrap-node-rpc; do echo waiting for tezos-bootstrap-node-rpc; sleep 2; done;
# wait for node to respond to rpc
until wget -O- http://tezos-bootstrap-node-rpc:8732/version; do sleep 2; done;

/usr/local/bin/tezos-client -A tezos-bootstrap-node-rpc -P 8732 -d /var/tezos/client -l --block genesis activate protocol "$PROTOCOL_HASH" with fitness -1 and key genesis and parameters /etc/tezos/parameters.json
