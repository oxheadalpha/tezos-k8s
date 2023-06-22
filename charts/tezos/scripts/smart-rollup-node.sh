set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
ROLLUP_DATA_DIR="$TEZ_VAR/rollup"
ROLLUP_DATA_DIR_PREIMAGES="$ROLLUP_DATA_DIR/wasm_2_0_0"

xxd -ps -c 0  /usr/local/share/tezos/evm_kernel/evm_installer.wasm   | tr -d '\n' > /var/tezos/smart-rollup-boot-sector
mkdir -p "$ROLLUP_DATA_DIR_PREIMAGES"
cp /usr/local/share/tezos/evm_kernel/* "$ROLLUP_DATA_DIR_PREIMAGES"
CMD="$TEZ_BIN/octez-smart-rollup-node-alpha \
  --endpoint http://tezos-node-rpc:8732 \
  -d $CLIENT_DIR \
  run operator for ${ROLLUP_ADDRESS} with operators ${OPERATOR_ACCOUNT} \
  --data-dir ${ROLLUP_DATA_DIR} \
  --boot-sector-file /var/tezos/smart-rollup-boot-sector \
  --rpc-addr 0.0.0.0"

exec $CMD
