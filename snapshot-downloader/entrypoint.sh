#!/bin/sh

set -ex

bin_dir="/usr/local/bin"

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
node="$bin_dir/tezos-node"

tezos_network=$(echo $CHAIN_PARAMS | jq -r ".network")
my_nodes_history_mode=$(echo $NODES | jq -r ".${MY_NODE_TYPE}.\"${MY_POD_NAME}\".config.shell.history_mode")
full_snapshot_url=$(echo $CHAIN_PARAMS | jq -r '.full_snapshot_url // empty')
rolling_snapshot_url=$(echo $CHAIN_PARAMS | jq -r '.rolling_snapshot_url // empty')

if [ "$my_nodes_history_mode" == "full" -a -n "$full_snapshot_url" ]; then
 snapshot_url="$full_snapshot_url"
elif [ "$my_nodes_history_mode" == "rolling" -a -n "$rolling_snapshot_url" ]; then
   snapshot_url="$rolling_snapshot_url"
else
  echo "No snapshot url provided for node"
  exit 0
fi

if [ -d ${node_data_dir}/context ]; then
    echo "Blockchain has already been imported, exiting"
    exit 0
else
    echo "Did not find pre-existing data, importing blockchain"
    mkdir -p ${node_data_dir}
    echo '{ "version": "0.0.4" }' > ${node_dir}/version.json
    cp -v /usr/local/share/tezos/alphanet_version ${node_dir}
    snapshot_file=${node_dir}/chain.snapshot
    curl -Lf -o $snapshot_file $snapshot_url
    ${node} snapshot import ${snapshot_file} --data-dir ${node_data_dir} --network $tezos_network --config-file /etc/tezos/config.json
    find ${node_dir}
    rm -rvf ${snapshot_file}
    echo ""
fi
