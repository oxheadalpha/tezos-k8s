echo "Writing custom configuration for public node"
mkdir -p /etc/tezos/data

#
# This is my comment.

/usr/local/bin/octez-node config init		\
    --config-file /etc/tezos/data/config.json	\
    --data-dir /etc/tezos/data			\
    --network $CHAIN_NAME

cat /etc/tezos/data/config.json

printf "\n\n\n\n\n\n\n"
