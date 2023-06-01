set -ex

TEZ_BIN=/usr/local/bin

CMD="$TEZ_BIN/octez-evm-proxy-server run"

exec $CMD
