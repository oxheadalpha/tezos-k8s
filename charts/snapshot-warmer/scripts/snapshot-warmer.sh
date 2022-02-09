#!/bin/bash

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0

HISTORY_MODE="${HISTORY_MODE}" yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

while true; do

  # Remove unlabeled snapshots
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' --selector='!history_mode')" -gt 0 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' --selector='!history_mode')
    printf "%s Number of snapshots without label is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --selector='!history_mode')
    SNAPSHOT_TO_DELETE=${SNAPSHOTS%% *}
    if ! kubectl delete volumesnapshots "${SNAPSHOT_TO_DELETE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOT_TO_DELETE}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    while [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; do
      if ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; then
        printf "%s Snapshot %s deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_TO_DELETE}"
      fi
    done

    sleep 10
  done

  # Maintain 5 snapshots of a certain history mode
  while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")" -gt 4 ]; do
    NUMBER_OF_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -o go-template='{{len .items}}' -l history_mode="${HISTORY_MODE}")
    printf "%s Number of snapshots for ${HISTORY_MODE}-node is too high at ${NUMBER_OF_SNAPSHOTS} deleting 1.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -l history_mode="${HISTORY_MODE}")
    SNAPSHOT_TO_DELETE=${SNAPSHOTS%% *}
    if ! kubectl delete volumesnapshots "${SNAPSHOT_TO_DELETE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOT_TO_DELETE}\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    while [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; do
      if ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_TO_DELETE}" --ignore-not-found)" ]; then
        printf "%s Snapshot %s deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_TO_DELETE}"
      fi
    done
  done
  
  sleep 5

  # Sometimes a snapshot will have no status, so we have to diff a list of all snapshots with a list of snapshots that have a status. There is no filter negation in Go JsonPath that Kubectl uses.
  SNAPSHOTS_WITH_STATUS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(@.status)].metadata.name}' -l history_mode="${HISTORY_MODE}")
  ALL_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[*].metadata.name}' -l history_mode="${HISTORY_MODE}")
  SNAPSHOTS_WITHOUT_STATUS=$(diff  <(echo "${ALL_SNAPSHOTS}" ) <(echo "${SNAPSHOTS_WITH_STATUS}"))

  # If no snapshots in progress and no snapshots without status then trigger a new EBS snapshot
  # only trigger if all snapshots are readyToUse=true
  if [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -l history_mode="${HISTORY_MODE}")" ] && ! [ "${SNAPSHOTS_WITHOUT_STATUS}" ]
  then
    # EBS Snapshot name based on current time and date
    SNAPSHOT_NAME=$(date "+%Y-%m-%d-%H-%M-%S" "$@")-$HISTORY_MODE-node-snapshot

    # Update volume snapshot name
    SNAPSHOT_NAME="${SNAPSHOT_NAME}" yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

    printf "%s Creating snapshot ${SNAPSHOT_NAME} in ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    # Start time for calculating EBS snapshot creation speed
    start_time=$(date +%s)

    # Create snapshot
    if ! kubectl apply -f createVolumeSnapshot.yaml
    then
        printf "%s ERROR creating volumeSnapshot ${SNAPSHOT_NAME} in ${NAMESPACE} .\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        exit 1
    fi

    # Give time for snapshot to be available in api
    sleep 5

    # while specific triggered snapshot is not ready
    while ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_NAME}" -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}')" ]; do
      # Get identifiers for in progress snapshot
      SNAPSHOT_CONTENT=$(kubectl get volumesnapshot "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
      EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
      EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
    
      # Get EBS snapshot progress, print, and wait if not finished
      printf "%s Snapshot %s is %s done.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}" "${EBS_SNAPSHOT_PROGRESS}"

      NEW_EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
      while [ "${NEW_EBS_SNAPSHOT_PROGRESS}" = "${EBS_SNAPSHOT_PROGRESS}" ]  && [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
        NEW_EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
      done

      # Snapshot may report 100% complete, but needs to be .status.readyToUse=true
      while ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_NAME}" -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}')" ] && [ "${EBS_SNAPSHOT_PROGRESS}" = 100% ]; do
        if [ "$(kubectl get volumesnapshots "${SNAPSHOT_NAME}" -o jsonpath='{.items[?(.status.readyToUse==true) ].metadata.name}')" ]; then
          printf "%s Snapshot %s is %s ready to use.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}" "${EBS_SNAPSHOT_PROGRESS}"
        fi
      done
    done

    # Snapshot finish time.
    end_time=$(date +%s)
    elapsed=$(( end_time - start_time ))
    printf "%s Snapshot ${SNAPSHOT_NAME} in ${NAMESPACE} finished.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    eval "echo EBS Snapshot finished in: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')\n"

  # If snapshot detected in progress
  else

    # We need a list of snapshots that might not have a status yet
    SNAPSHOTS_WITH_STATUS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(@.status)].metadata.name}' -l history_mode="${HISTORY_MODE}")
    ALL_SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[*].metadata.name}' -l history_mode="${HISTORY_MODE}")
    SNAPSHOTS_WITHOUT_STATUS=$(diff  <(echo "${ALL_SNAPSHOTS}" ) <(echo "${SNAPSHOTS_WITH_STATUS}"))

    # while any snapshot is not ready
    while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' -l history_mode="${HISTORY_MODE}")" ] || [ "${SNAPSHOTS_WITHOUT_STATUS}" ]; do
      if [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' -l history_mode="${HISTORY_MODE}"| wc -w)" -gt 1 ]  || [ "$(echo "${SNAPSHOTS_WITHOUT_STATUS}" |  wc -w)" -gt 1 ]; then
        printf "%s Too many snapshots in progress or no status.  Waiting for all snapshots to finish.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      else
        # Get identifiers for in progress snapshot
        SNAPSHOT_NAME=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' -l history_mode="${HISTORY_MODE}")
        SNAPSHOT_CONTENT=$(kubectl get volumesnapshot "${SNAPSHOT_NAME}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
        EBS_SNAPSHOT_ID=$(kubectl get volumesnapshotcontent "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.snapshotHandle}')
        EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
      
        # Get EBS snapshot progress, print, and wait if not finished
        printf "%s Snapshot %s is %s done.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}" "${EBS_SNAPSHOT_PROGRESS}"

        NEW_EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
        while [ "${NEW_EBS_SNAPSHOT_PROGRESS}" = "${EBS_SNAPSHOT_PROGRESS}" ]  && [ "${EBS_SNAPSHOT_PROGRESS}" != 100% ]; do
          NEW_EBS_SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --snapshot-ids "${EBS_SNAPSHOT_ID}" --query "Snapshots[*].[Progress]" --output text)
        done

        # Snapshot may report 100% complete, but needs to be .status.readyToUse=true
        while ! [ "$(kubectl get volumesnapshots "${SNAPSHOT_NAME}" -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}')" ] && [ "${EBS_SNAPSHOT_PROGRESS}" = 100% ]; do
          if [ "$(kubectl get volumesnapshots "${SNAPSHOT_NAME}" -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}')" ]; then
            printf "%s Snapshot %s is %s ready to use.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${SNAPSHOT_NAME}" "${EBS_SNAPSHOT_PROGRESS}"
          fi
        done
      fi
    done
  fi
done   