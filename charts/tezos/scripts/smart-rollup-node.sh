set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
ROLLUP_DATA_DIR="$TEZ_VAR/rollup"

xxd -ps -c 0  /usr/local/share/tezos/evm_kernel.wasm   | tr -d '\n' > /var/tezos/smart-rollup-boot-sector
CMD="$TEZ_BIN/octez-smart-rollup-node-alpha \
  --endpoint http://tezos-node-rpc:8732 \
  -d $CLIENT_DIR \
  run operator for ${ROLLUP_ADDRESS} with operators ${OPERATOR_ACCOUNT} \
  --data-dir ${ROLLUP_DATA_DIR} \
  --boot-sector-file /var/tezos/smart-rollup-boot-sector \
  --rpc-addr 0.0.0.0"

exec $CMD
