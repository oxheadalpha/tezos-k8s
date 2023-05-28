set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

touch /var/tezos/smart-rollup-boot-sector
CMD="$TEZ_BIN/octez-smart-rollup-node-alpha --endpoint http://tezos-node-rpc:8732 -d $CLIENT_DIR run operator for ${ROLLUP_ADDRESS} with operators ${OPERATOR_ACCOUNT} --boot-sector-file /var/tezos/smart-rollup-boot-sector"

exec $CMD
