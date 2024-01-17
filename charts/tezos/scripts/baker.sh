set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"
BAKER_EXTRA_ARGS_FROM_ENV=${BAKER_EXTRA_ARGS}

proto_command="{{ .command_in_tpl }}"

my_baker_account="$(sed -n "$(($BAKER_INDEX + 1))p" < /etc/tezos/baker-account )"

if [ "${my_baker_account}" == "" ]; then
  while true; do
    printf "This container is not baking, but exists "
    printf "due to uneven numer of bakers within the statefulset\n"
    sleep 300
  done
fi

per_block_vote_file=/etc/tezos/baker-config/${my_baker_account}-${proto_command}-per-block-votes.json

if [ ! -f "$per_block_vote_file" ]; then
  echo "Error: $per_block_vote_file not found" >&2
  exit 1
fi

if [ "$(cat $per_block_vote_file)" == "null" ]; then
  cat << EOF
You must pass per-block-votes (such as liquidity_baking_toggle_vote) in values.yaml, for example:
protocols:
- command: ${proto_command}
  vote:
    liquidity_baking_toggle_vote: "on"
EOF
  exit 1
fi
extra_args="--votefile ${per_block_vote_file}"

if [ -f /etc/tezos/baker-config/${my_baker_account}_operations_pool ]; then
  extra_args="${extra_args} --operations-pool $(cat /etc/tezos/baker-config/${my_baker_account}_operations_pool)"
fi

if [ -f /etc/tezos/baker-config/${my_baker_account}_dal_node_rpc_url ]; then
  extra_args="${extra_args} --dal-node $(cat /etc/tezos/baker-config/${my_baker_account}_dal_node_rpc_url)"
fi

CLIENT="$TEZ_BIN/octez-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/octez-baker-$proto_command -d $CLIENT_DIR"

# ensure we can run octez-client commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-client

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

exec $CMD run with local node $NODE_DATA_DIR ${extra_args} ${BAKER_EXTRA_ARGS_FROM_ENV} ${my_baker_account}
