set -ex

TEZ_BIN=/usr/local/bin

CMD="$TEZ_BIN/octez-evm-node run proxy \
  with endpoint http://rollup-${MY_POD_NAME}:8932 \
  --rpc-addr 0.0.0.0"

exec $CMD
