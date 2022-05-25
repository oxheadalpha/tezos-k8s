#!/bin/sh

bail() {
    echo "ERROR: $@" 1>&2
    exit 1
}

snapshot() {
    URL="$1"

    echo "Downloading snapshot $URL"
    echo '{ "version": "0.0.4" }' > "$node_dir/version.json"
    curl -LfsS -o "$snapshot_file" "$URL"
}

tarball() {
    URL="$1"

    echo "Downloading and extracting tarball from $URL"
    curl -LfsS "$URL" | lz4 -d | tar -x -C "$data_dir"
    rm -fv "$node_data_dir/identity.json"
}

set -e

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

if [ ! -d "$data_dir" ]; then
  bail "/var/tezos doesn't exist. There should be a volume mounted."
fi

if [ -d "$node_data_dir/context" ]; then
  echo "Blockchain has already been imported. Exiting."
  exit 0
fi

echo "Did not find a pre-existing blockchain."

HISTORY_MODE=$(< /etc/tezos/config.json jq -r "
			.shell.history_mode
			|if type == \"object\" then
				(keys|.[0])
			 else .
			 end")

echo "My nodes history mode: '$HISTORY_MODE'"

SNAPSHOT_TYPE=$(echo $NODES | jq -r ".\"$MY_NODE_CLASS\".snapshot")
if [ "$SNAPSHOT_TYPE" = null ]; then
  SNAPSHOT_TYPE=$(echo $NODE_GLOBALS | jq -r .snapshot)
fi

SNAPSHOT_URL=$(echo $SNAPSHOTS  | jq -r ".$HISTORY_MODE.$SNAPSHOT_TYPE//\"\"")

#
# XXX: we override here with the old way of defining these URLs
#      for backwards compatibility:

case "$HISTORY_MODE" in
  full)     snapshot_url="$FULL_SNAPSHOT_URL"
            tarball_url="$FULL_TARBALL_URL";;
  rolling)  snapshot_url="$ROLLING_SNAPSHOT_URL"
            tarball_url="$ROLLING_TARBALL_URL";;
  archive)  tarball_url="$ARCHIVE_TARBALL_URL";;
  *)        echo "Invalid node history mode: '$HISTORY_MODE'"
            exit 1;;
esac

if [ -n "$snapshot_url" ] && [ -n "$tarball_url" ]; then
  bail "Only a snapshot or tarball url may be specified per history mode."
fi

if [ -z "$SNAPSHOT_TYPE" -a -n "$snapshot_url" ]; then
  SNAPSHOT_TYPE=snapshot
  SNAPSHOT_URL="$snapshot_url"
fi

if [ -z "$SNAPSHOT_TYPE" -a -n "$tarball_url" ]; then
  SNAPSHOT_TYPE=tarball
  SNAPSHOT_URL="$tarball_url"
fi

#
# XXX: end of backwards compat.

mkdir -p "$node_data_dir"

case "$SNAPSHOT_TYPE" in
snapshot)	if [ "$HISTORY_MODE" = archive ]; then
		    bail "Regular snapshots can't do archive mode, " \
		         "use tarball instead."
		fi
		snapshot "$SNAPSHOT_URL";;
tarball)	tarball "$SNAPSHOT_URL";;
none)		;;
*)		usage "$SNAPSHOT_TYPE must be 'snapshot', 'tarball',"
		      "or 'none'.";;
esac

chown -R 100 "$data_dir"
ls -lR "$data_dir"
