#!/bin/sh

set -e

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

if [ ! -d "$data_dir" ]; then
  echo "ERROR: /var/tezos doesn't exist. There should be a volume mounted."
  exit 1
fi

if [ -d "$node_data_dir/context" ]; then
  echo "Blockchain has already been imported. Exiting."
  exit 0
fi

echo "Did not find a pre-existing blockchain."

my_nodes_history_mode=$(< /etc/tezos/config.json jq -r "
				.shell.history_mode
				|if type == \"object\" then
					(keys|.[0])
				 else .
				 end")

echo "My nodes history mode: '$my_nodes_history_mode'"

snapshot_url=""
tarball_url=""
case "$my_nodes_history_mode" in
  full)     snapshot_url="$FULL_SNAPSHOT_URL";;

  rolling)  snapshot_url="$ROLLING_SNAPSHOT_URL"
            tarball_url="$ROLLING_TARBALL_URL";;

  archive)  tarball_url="$ARCHIVE_TARBALL_URL";;

  *)        echo "Invalid node history mode: '$my_nodes_history_mode'"
            exit 1;;
esac

if [ -z "$snapshot_url" ] && [ -z "$tarball_url" ]; then
  echo "ERROR: No snapshot or tarball url specified."
  exit 1
fi

if [ -n "$snapshot_url" ] && [ -n "$tarball_url" ]; then
  echo "ERROR: Either only a snapshot or tarball url may be specified per Tezos node history mode."
fi

rm -rfv "$node_data_dir"
mkdir -p "$node_data_dir"

if [ -n "$snapshot_url" ]; then
  echo "Downloading $snapshot_url"
  echo '{ "version": "0.0.4" }' > "$node_dir/version.json"
  curl -LfsS -o "$snapshot_file" "$snapshot_url"
elif [ -n "$tarball_url" ]; then
  echo "Downloading and extracting tarball from $tarball_url"
  curl -LfsS "$tarball_url" | lz4 -d | tar -x -C "$data_dir"
  rm -fv "$node_data_dir/identity.json"
fi

chown -R 100 "$data_dir"
ls -lR "$data_dir"
