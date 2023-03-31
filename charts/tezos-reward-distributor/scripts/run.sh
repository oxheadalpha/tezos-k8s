#!/bin/sh

if [ "${DRY_RUN}" == "false" ]; then
  dry_run_arg=""
else
  dry_run_arg="--dry_run"
fi
python src/main.py \
  -M 2 \
  --reward_data_provider ${REWARD_DATA_PROVIDER} \
  --node_addr_public ${TEZOS_NODE_ADDR} \
  --node_endpoint ${TEZOS_NODE_ADDR} \
  --base_directory /trd \
  --signer_endpoint ${SIGNER_ADDR} \
  --release_override ${RELEASE_OVERRIDE} \
  --initial_cycle ${INITIAL_CYCLE} \
  -N ${NETWORK} \
  ${EXTRA_TRD_ARGS} \
  ${dry_run_arg}
