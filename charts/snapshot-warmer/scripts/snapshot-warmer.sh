#!/bin/sh

cd /

yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
export PERSISTENT_VOLUME_CLAIM="var-volume-snapshot-$HISTORY_MODE-node-0"
yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

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

  if ! [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")" ]
  then
    # EBS Snapshot name based on current time and date
    current_date=$(date "+%Y-%m-%d-%H-%M-%S" "$@")
    export SNAPSHOT_NAME="$current_date-$HISTORY_MODE-node-snapshot"
    # Update volume snapshot name
    yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

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
      printf "%s Snapshot is still creating...n" "$(date "+%Y-%m-%d %H:%M:%S\n" "$@")"
      sleep 10
      # # Get EBS snapshot progress
      # SNAPSHOT_CONTENT=$(kubectl get volumesnapshot -n "${NAMESPACE}" "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
      # EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent -n "${NAMESPACE}" "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
      # EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)

      # while [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
      #   printf "%s Snapshot is still creating...%s\n" "$(date "+%Y-%m-%d %H:%M:%S\n" "$@")" "${EBS_SNAPSHOT_PROGRESS}"
      #     if [ "${HISTORY_MODE}" = archive ]; then
      #       sleep 1m
      #     else
      #       sleep 10
      #     fi
      # done

    done
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    printf "%s Snapshot ${SNAPSHOT_NAME} in ${NAMESPACE} finished." "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')\n"
  else
    printf "%s Snapshot already in progress...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 10
    # SNAPSHOT_NAME=$(kubectl  aget volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")
    # printf "%s Snapshot is %s.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}"
    # # Get EBS snapshot progress
    # SNAPSHOT_CONTENT=$(kubectl get volumesnapshot -n "${NAMESPACE}" "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
    # EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent -n "${NAMESPACE}" "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
    # EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)

    # if [ "${EBS_SNAPSHOT_PROGRESS}" ];then
    #   while [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
    #     printf "%s Snapshot is still creating...%s\n" "$(date "+%Y-%m-%d %H:%M:%S\n" "$@")" "${EBS_SNAPSHOT_PROGRESS}"
    #       if [ "${HISTORY_MODE}" = archive ]; then
    #         sleep 1m
    #       else
    #         sleep 10
    #       fi
    #   done
    # fi
  fi
done
