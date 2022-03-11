set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

proto_command="{{ .command_in_tpl }}"

echo '{"liquidity_baking_toggle_vote": "pass"}' > /etc/tezos/per_block_votes.json

if [ "${DAEMON}" == "baker" ]; then
    # we pass both a vote argument and a votefile argument; vote argument is mandatory as a fallback
    extra_args="with local node $NODE_DATA_DIR --liquidity-baking-toggle-vote on --votefile /etc/tezos/per_block_votes.json"
fi

my_baker_account="$(cat /etc/tezos/baker-account )"

CLIENT="$TEZ_BIN/tezos-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/tezos-$DAEMON-$proto_command -d $CLIENT_DIR"

# ensure we can run tezos-client commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-client

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

exec $CMD run ${extra_args} ${my_baker_account}
