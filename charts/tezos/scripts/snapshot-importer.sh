set -ex

bin_dir="/usr/local/bin"

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
node="$bin_dir/tezos-node"
snapshot_file=${node_dir}/chain.snapshot

if [ -d ${node_data_dir}/context ]; then
    echo "Blockchain has already been imported, exiting"
    exit 0
fi

${node} snapshot import ${snapshot_file} --data-dir ${node_data_dir} \
    --network $CHAIN_NAME --config-file /etc/tezos/config.json
find ${node_dir}
rm -rvf ${snapshot_file}
