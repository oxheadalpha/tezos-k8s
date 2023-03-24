set -e

bin_dir="/usr/local/bin"
data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
node="$bin_dir/octez-node"
snapshot_file=${node_dir}/chain.snapshot

if [ ! -f ${snapshot_file} ]; then
    echo "No snapshot to import."
    exit 0
fi

if [ -e ${node_data_dir}/context/store.dict ]; then
    echo "Blockchain has already been imported. If a tarball"
    echo "instead of a regular tezos snapshot was used, it was"
    echo "imported in the snapshot-downloader container."
    exit 0
fi

cp -v /etc/tezos/config.json ${node_data_dir}

if [ -f ${node_dir}/chain.snapshot.block_hash ]; then
    block_hash_arg="--block $(cat ${node_dir}/chain.snapshot.block_hash)"
fi

${node} snapshot import ${snapshot_file} --data-dir ${node_data_dir}
find ${node_dir}

rm -rvf ${snapshot_file}
