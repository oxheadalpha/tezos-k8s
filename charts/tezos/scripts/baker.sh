set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

proto_command="{{ .command_in_tpl }}"

my_baker_account="$(cat /etc/tezos/baker-account )"

CLIENT="$TEZ_BIN/tezos-client -d $CLIENT_DIR"
CMD="$TEZ_BIN/tezos-baker-$proto_command -d $CLIENT_DIR"

# ensure we can run tezos-client commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-client

while ! $CLIENT rpc get chains/main/blocks/head; do
    sleep 5
done

exec $CMD run with local node $NODE_DATA_DIR ${my_baker_account}
