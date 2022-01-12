#!/bin/sh

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml

# hangzhounet-shots PVC is called 'var-volume-archive-node' for some reason
HISTORY_MODE=$(kubectl get pods -n "${NAMESAPCE}" -l appType=tezos-node -o jsonpath="{.items[0].metadata.labels.node_class_history_mode}")
if [ "$HISTORY_MODE" ]; then
    PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0
else
    PERSISTENT_VOLUME_CLAIM=var-volume-tezos-node-0
fi

PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

while true; do

  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{ "{{" }}len .items{{ "}}" }}')" -gt 4 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{ "{{" }}len .items{{ "}}" }}')
    printf "%s Number of snapshots is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}")
    if ! kubectl delete volumesnapshots "${SNAPSHOTS%% *}" --namespace "${NAMESPACE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOTS%% *}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    sleep 10
  done
  
  if ! [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}")" ]
  then
    # EBS Snapshot name based on current time and date
    SNAPSHOT_NAME=$(date "+%Y-%m-%d-%H-%M-%S" "$@")-node-snapshot

    # Update volume snapshot name
    SNAPSHOT_NAME="${SNAPSHOT_NAME}" yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

    printf "%s Creating snapshot ${SNAPSHOT_NAME} in ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    start_time=$(date +%s)

    # Create snapshot
    if ! kubectl apply -f createVolumeSnapshot.yaml
    then
        printf "%s ERROR creating volumeSnapshot ${SNAPSHOT_NAME} in ${NAMESPACE} .\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        exit 1
    fi

    sleep 5

    # While no snapshots ready
    while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}")" ]; do
      printf "%s Snapshot is still creating...\n" "$(date "+%Y-%m-%d %H:%M:%S\n" "$@")"
      sleep 5
    done
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    printf "%s Snapshot ${SNAPSHOT_NAME} in ${NAMESPACE} finished." "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')\n"
  else
    printf "%s Waiting for current snapshot to finish...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 30
  fi
done   