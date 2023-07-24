#!/bin/sh

if [ "${DRY_RUN}" == "false" ]; then
  dry_run_arg=""
else
  dry_run_arg="--dry_run"
fi
if [ "${ADJUSTED_EARLY_PAYOUTS}" == "false" ]; then
  aep_arg=""
else
  aep_arg="--adjusted_early_payouts"
fi
python src/main.py \
  -M 2 \
  --reward_data_provider ${REWARD_DATA_PROVIDER} \
  --node_addr_public ${TEZOS_NODE_ADDR} \
  --node_endpoint ${TEZOS_NODE_ADDR} \
  --base_directory /trd \
  --signer_endpoint ${SIGNER_ADDR} \
  --initial_cycle ${INITIAL_CYCLE} \
  -N ${NETWORK} \
  ${EXTRA_TRD_ARGS} \
  ${dry_run_arg} \
  ${aep_arg}
