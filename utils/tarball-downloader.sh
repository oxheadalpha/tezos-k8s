#!/bin/sh

set -e

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"


if [ -d /var/tezos ] ; then
  if [ ! -d $node_data_dir/context ]; then
    echo "Did not find pre-existing data, importing blockchain"
    rm -rf $node_data_dir
    mkdir -p $node_data_dir
    curl $TARBALL_URL | lz4 -d | tar -x -C /var/tezos
    rm $node_data_dir/identity.json
  fi
else
  echo "/var/tezos does not exist."
  echo "Error!" 1>&2
  exit 1
fi

chown -R 100 /var/tezos
ls -lR /var/tezos