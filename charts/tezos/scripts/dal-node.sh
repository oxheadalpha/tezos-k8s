set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
DAL_DATA_DIR="$TEZ_VAR/dal"

mkdir -p ${DAL_DATA_DIR}
$TEZ_BIN/octez-dal-node \
  init-config \
  --data-dir ${DAL_DATA_DIR} \
  --net-addr 0.0.0.0:11732 \
  --rpc-addr 0.0.0.0 \
  --rpc-port 10732 \
  --use-unsafe-srs-for-tests

CMD="$TEZ_BIN/octez-dal-node \
  --endpoint http://tezos-node-rpc:8732 \
  run \
  --data-dir ${DAL_DATA_DIR}"

exec $CMD
