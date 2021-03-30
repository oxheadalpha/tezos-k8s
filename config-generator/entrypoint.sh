#!/bin/sh -x

ls -l /etc/tezos/data
echo ------------------------------------------------------------
cat /etc/tezos/data/config.json
echo ------------------------------------------------------------

mkdir -p /var/tezos/client
chmod -R 777 /var/tezos/client
python3 /entrypoint.py $@

#
# Next we write the current baker ccount into /etc/tezos/baking-account.
# We do it here because we shall use jq to process some of the environment
# variables and we are not guaranteed to have jq available on an arbitrary
# tezos docker image.

my_baker_account=$(echo $NODES | \
	jq -r ".${MY_NODE_TYPE}.\"${MY_POD_NAME}\".bake_using_account")

# If no account to bake for was specified in the node's settings,
# config-generator defaults the account name to the pod's name.
if [ "$my_baker_account" = null ]; then
    my_baker_account="$MY_POD_NAME"
fi

echo "$my_baker_account" > /etc/tezos/baker-account

#
# If we are snapshotting, we download the snapshot here because the snapshot
# container is not guaranteed to have curl.

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

my_nodes_history_mode=$(echo $NODES |
	jq -r ".$MY_NODE_TYPE.\"$MY_POD_NAME\".config.shell.history_mode")

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
	cp -v /usr/local/share/tezos/alphanet_version $node_dir
	curl -Lf -o $snapshot_file $snapshot_url
fi

chown -R 100 /var/tezos
ls -lR /var/tezos
