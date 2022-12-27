set -ex

if [ ! -e /var/tezos/node/data/context ]
then
  printf "No context in data dir found, probably initial start, doing nothing."
  exit 0
fi
octez-node upgrade storage --data-dir /var/tezos/node/data
