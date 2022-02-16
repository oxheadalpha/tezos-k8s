#!/bin/sh

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0

HISTORY_MODE="${HISTORY_MODE}" yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

while true; do

  # Remove unlabeled snapshots
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{len .items}}' --selector='!history_mode')" -gt 0 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{len .items}}' --selector='!history_mode')
    printf "%s Number of snapshots without label is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" --selector='!history_mode')
    if ! kubectl delete volumesnapshots "${SNAPSHOTS%% *}" --namespace "${NAMESPACE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOTS%% *}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    sleep 10
  done

  # Maintain 4 snapshots of a certain history mode
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")" -gt 4 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")
    printf "%s Number of snapshots for ${HISTORY_MODE}-node is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")
    if ! kubectl delete volumesnapshots "${SNAPSHOTS%% *}" --namespace "${NAMESPACE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOTS%% *}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    sleep 10
  done
  
  # If there are no unready snapshots then trigger a new snapshot
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

    # Snapshot doesnt exist yet (Cant use kubectl wait)
    if ! [ "$(kubectl get volumesnapshot "${SNAPSHOT_NAME}")" ]; then
      printf "%s Waiting for VolumeSnapshot ${SNAPSHOT_NAME} to exist.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        # Wait for snapshot to exist (cant use kubectl wait)
        while ! [ "$(kubectl get volumesnapshot "${SNAPSHOT_NAME}")" ]; do
          sleep 1
        done
    fi

    # Snapshot does exist
    # Separate if because it could be immediately be available and we want to report that status.
    if [ "$(kubectl get volumesnapshot "${SNAPSHOT_NAME}")" ]; then
      printf "%s VolumeSnapshot ${SNAPSHOT_NAME} exists!\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      printf "%s Waiting for VolumeSnapshot ${SNAPSHOT_NAME} to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      # Get EBS snapshot progress
      SNAPSHOT_CONTENT=$(kubectl get volumesnapshot -n "${NAMESPACE}" "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
      EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent -n "${NAMESPACE}" "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
      EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)

      printf "%s VolumeSnapshot ${SNAPSHOT_NAME} is %s done.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${EBS_SNAPSHOT_PROGRESS}"

      while [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
        OLD_PROGRESS=$EBS_SNAPSHOT_PROGRESS
        while [ "${OLD_PROGRESS}" = "${EBS_SNAPSHOT_PROGRESS}" ]; do
          EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
          if [ "${OLD_PROGRESS}" != "${EBS_SNAPSHOT_PROGRESS}" ]; then
            printf "%s VolumeSnapshot ${SNAPSHOT_NAME} is %s done.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${EBS_SNAPSHOT_PROGRESS}"
          fi
        done
      done

      printf "%s Waiting for VolumeSnapshot ${SNAPSHOT_NAME} to be ready to use.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      kubectl wait volumesnapshot "${SNAPSHOT_NAME}" --for=jsonpath='{.status.readyToUse}'=true
    fi

    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    printf "%s Snapshot ${SNAPSHOT_NAME} in ${NAMESPACE} finished." "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')\n"
    
  else
    printf "%s Snapshot already in progress...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 10
  fi
done   