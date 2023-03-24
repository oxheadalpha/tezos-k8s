set -e

echo "Writing custom configuration for public node"
mkdir -p /etc/tezos/data

# if config already exists (container is rebooting), dump and delete it.
if [ -e /etc/tezos/data/config.json ]; then
  printf "Found pre-existing config.json:\n"
  cat /etc/tezos/data/config.json
  printf "Deleting\n"
  rm -rvf /etc/tezos/data/config.json
fi

/usr/local/bin/octez-node config init		\
    --config-file /etc/tezos/data/config.json	\
    --data-dir /etc/tezos/data			\
    --network $CHAIN_NAME

cat /etc/tezos/data/config.json

printf "\n\n\n\n\n\n\n"
