#!/bin/sh

set -x

bin_dir="/usr/local/bin"

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
node="$bin_dir/tezos-node"

tezos_network=$(echo $CHAIN_PARAMS | jq -r '.network')
snapshot_url=$(echo $CHAIN_PARAMS | jq -r '.snapshot_url')
if [ -d ${node_dir}/data/context ]; then
    echo "Blockchain has already been imported, exiting"
    exit 0
elif [ -z "$snapshot_url" ]; then
    echo "No snapshot was passed as parameter, exiting"
    exit 0
else
    echo "Did not find pre-existing data, importing blockchain"
    mkdir -p ${node_dir}/data
    echo '{ "version": "0.0.4" }' > ${node_dir}/version.json
    cp -v /usr/local/share/tezos/alphanet_version ${node_dir}
    snapshot_file=${node_dir}/chain.snapshot
    curl -L -o $snapshot_file $snapshot_url
    exec "${node}" snapshot import ${snapshot_file} --data-dir ${node_data_dir} --network $tezos_network --config-file /etc/tezos/config.json
    find ${node_dir}
    rm -rvf ${snapshot_file}
    echo ""
fi
