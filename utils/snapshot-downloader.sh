#!/bin/sh

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

my_nodes_history_mode=$(echo $NODES | jq -r "
				.\"${MY_NODE_CLASS}\"
				.instances[${MY_POD_NAME#$MY_NODE_CLASS-}]
				.config.shell.history_mode")

echo My nodes history mode: $my_nodes_history_mode

case "$my_nodes_history_mode" in
        full)           snapshot_url="$FULL_SNAPSHOT_URL"       ;;
        rolling)        snapshot_url="$ROLLING_SNAPSHOT_URL"    ;;
esac

curl https://tezos-snapshots.s3-accelerate.amazonaws.com/vol-00e24ee0c708bcce9/2021-09-13T16%3A58%3A16%2B00%3A00+snap-0074628953cabfaae+-+grenadanet-archive-snapshot.tar.lz4 | lz4 -d | tar -x -C /var/tezos

if [ ! -d $node_data_dir/context ]; then
	echo "Did not find pre-existing data, importing blockchain"
	mkdir -p $node_data_dir
	echo '{ "version": "0.0.4" }' > $node_dir/version.json
	cp -v /usr/local/share/tezos/alphanet_version $node_dir
	curl -Lf -o $snapshot_file $snapshot_url
fi

chown -R 100 /var/tezos
ls -lR /var/tezos
