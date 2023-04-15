set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

CMD="$TEZ_BIN/octez-smart-rollup-node-alpha -d $CLIENT_DIR run operator for ${ROLLUP_ADDRESS} with operators ${OPERATOR_ACCOUNT}"

# ensure we can run tezos-signer commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-signer

exec $CMD
