set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

proto_command="{{ .command_in_tpl }}"

if [ "${DAEMON}" == "baker" ]; then
    extra_args="with local node $NODE_DATA_DIR"
fi

my_baker_account="$(cat /etc/tezos/baker-account )"

CLIENT="$TEZ_BIN/tezos-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/tezos-$DAEMON-$proto_command -d $CLIENT_DIR"

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

exec $CMD run ${extra_args} ${my_baker_account}
