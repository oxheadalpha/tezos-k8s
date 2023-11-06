set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
CLIENT_DIR="$TEZ_VAR/client"
NODE_DIR="$TEZ_VAR/node"
NODE_DATA_DIR="$TEZ_VAR/node/data"

extra_args=""
if [ -f ${CLIENT_DIR}/authorized_keys ]; then
  extra_args="${extra_args} --require-authentication"
fi
CMD="$TEZ_BIN/octez-signer -d $CLIENT_DIR ${extra_args} launch http signer -a 0.0.0.0 -p 6732"

# ensure we can run tezos-signer commands without specifying client dir
ln -s /var/tezos/client /home/tezos/.tezos-signer

exec $CMD
