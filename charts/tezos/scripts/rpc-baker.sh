set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
BAKER_EXTRA_ARGS_FROM_ENV=${BAKER_EXTRA_ARGS}
mkdir -p $CLIENT_DIR

per_block_vote_file=/etc/tezos/baker-config/${BAKER_NAME}-${PROTO_COMMAND}-per-block-votes.json

if [ ! -f "$per_block_vote_file" ]; then
  echo "Error: $per_block_vote_file not found" >&2
  exit 1
fi

extra_args="--votefile ${per_block_vote_file}"

if [ "${OPERATIONS_POOL}" != "" ]; then
  extra_args="${extra_args} --operations-pool ${OPERATIONS_POOL}"
fi

if [ "${DAL_NODE_RPC_URL}" != "" ]; then
  extra_args="${extra_args} --dal-node ${DAL_NODE_RPC_URL}"
fi

CLIENT="$TEZ_BIN/octez-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/octez-baker-${PROTO_COMMAND} -d $CLIENT_DIR"

# ensure we can run octez-client commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-client

exec $CMD --endpoint ${NODE_RPC_URL} run remotely  ${extra_args} ${BAKER_EXTRA_ARGS_FROM_ENV} ${BAKE_USING_ACCOUNTS}
