#!/bin/sh

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0

HISTORY_MODE="${HISTORY_MODE}" yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
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
  
  if ! [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")" ]
  then
    # EBS Snapshot name based on current time and date
    SNAPSHOT_NAME=$(date "+%Y-%m-%d-%H-%M-%S" "$@")-$HISTORY_MODE-node-snapshot

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
    while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")" ]; do
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