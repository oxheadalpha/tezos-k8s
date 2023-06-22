set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
DAL_DATA_DIR="$TEZ_VAR/dal"

mkdir -p ${DAL_DATA_DIR}

CMD="$TEZ_BIN/octez-dal-node \
  run \
  --data-dir ${DAL_DATA_DIR} \
  --endpoint http://tezos-node-rpc:8732 \
  --net-addr 0.0.0.0:11732 \
  --rpc-addr 0.0.0.0:10732"

exec $CMD
