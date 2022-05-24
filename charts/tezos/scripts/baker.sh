set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

proto_command="{{ .command_in_tpl }}"

if [ "${proto_command}" == "012-Psithaca" ]; then
    extra_args=""
else
    per_block_vote_file=/etc/tezos/per-block-votes/${proto_command}-per-block-votes.json
    if [ $(cat $per_block_vote_file) == "null" ]; then
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
fi

my_baker_account="$(cat /etc/tezos/baker-account )"

CLIENT="$TEZ_BIN/tezos-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/tezos-baker-$proto_command -d $CLIENT_DIR"

# ensure we can run tezos-client commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-client

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

exec $CMD run with local node $NODE_DATA_DIR ${extra_args} ${my_baker_account}
