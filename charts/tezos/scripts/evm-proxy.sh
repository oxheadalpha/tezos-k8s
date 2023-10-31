set -ex

TEZ_BIN=/usr/local/bin

if ls /usr/local/bin/octez-evm-node; then
  CMD="$TEZ_BIN/octez-evm-node run proxy \
    with endpoint http://rollup-${MY_POD_NAME}:8932 \
    --mode dev \
    --rpc-addr 0.0.0.0"
else
  # temporary until 20231106 mondaynet - old command
  CMD="$TEZ_BIN/octez-evm-proxy-server run \
    with endpoint http://rollup-${MY_POD_NAME}:8932 \
    --mode dev \
    --rpc-addr 0.0.0.0"
fi

exec $CMD
