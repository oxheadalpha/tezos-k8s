#!/bin/sh

set -e

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

my_nodes_history_mode=$(echo $NODES | jq -r "
				.\"${MY_NODE_CLASS}\"
				.instances[${MY_POD_NAME#$MY_NODE_CLASS-}]
				.config.shell.history_mode
				|if type == \"object\" then
					(keys|.[0])
				 else .
				 end")

echo My nodes history mode: $my_nodes_history_mode

case "$my_nodes_history_mode" in
        full)           snapshot_url="$FULL_SNAPSHOT_URL"       ;;
        rolling)        snapshot_url="$ROLLING_SNAPSHOT_URL"    ;;
        *)              echo "No snapshot URL provide for node, exiting"
                        exit 1;;
esac

if [ ! -d $node_data_dir/context ]; then
	echo "Did not find pre-existing data, importing blockchain"
	mkdir -p $node_data_dir
	echo '{ "version": "0.0.4" }' > $node_dir/version.json
	curl -Lf -o $snapshot_file $snapshot_url
fi

chown -R 100 /var/tezos
ls -lR /var/tezos
