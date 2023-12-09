set -ex

TEZ_VAR=/var/tezos
TEZ_BIN=/usr/local/bin
DAL_DATA_DIR="$TEZ_VAR/dal"

mkdir -p ${DAL_DATA_DIR}

extra_args=""
if [ "${BOOTSTRAP_PROFILE}" == "true" ]; then
  extra_args="--bootstrap-profile"
fi
if [ "${ATTESTER_PROFILES}" != "" ]; then
  extra_args="${extra_args} --attester-profiles ${ATTESTER_PROFILES}"
fi
if [ "${PEER}" != "" ]; then
  extra_args="${extra_args} --peer ${PEER}"
fi
if [ "${PUBLIC_ADDR}" != "" ]; then
  extra_args="${extra_args} --public-addr ${PUBLIC_ADDR}"
fi
# populate identity, if provided
if [ -n "$IDENTITY_JSON" ]; then
    identity_path=/var/tezos/dal/identity.json
    printf "Found persistent identity, writing to $identity_path"
    echo "$IDENTITY_JSON" >  $identity_path
fi
#

CMD="$TEZ_BIN/octez-dal-node run ${extra_args} --data-dir ${DAL_DATA_DIR} \
  --endpoint http://tezos-node-rpc:8732 \
  --net-addr 0.0.0.0:11732 \
  --rpc-addr 0.0.0.0:10732"

exec $CMD
