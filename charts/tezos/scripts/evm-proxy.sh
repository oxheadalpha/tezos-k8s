set -ex

TEZ_BIN=/usr/local/bin

CMD="$TEZ_BIN/octez-evm-proxy-server run \
  --rpc-addr 0.0.0.0 \
  --rollup-node-endpoint  http://rollup-evm:8932"

exec $CMD
