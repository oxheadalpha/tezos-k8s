set -ex

if [ ! -e /var/tezos/node/data ]
then
  printf "No data dir found, probably initial start, doing nothing."
  exit 0
fi
tezos-node upgrade storage --data-dir /var/tezos/node/data
