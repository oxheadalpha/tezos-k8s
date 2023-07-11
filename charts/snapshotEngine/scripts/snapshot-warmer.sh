#!/bin/sh

cd /

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

getSnapshotNames() {
  local readyToUse="${1##readyToUse=}"
  shift
  if [ -z "$readyToUse" ]; then
    echo "Error: No jsonpath for volumesnapshots' ready status was provided."
    exit 1
  fi
  kubectl get volumesnapshots -o jsonpath="{.items[?(.status.readyToUse==$readyToUse)].metadata.name}" --namespace "$NAMESPACE" "$@"
}

getNumberOfSnapshots() {
  local readyToUse="$1"
  shift
  getSnapshotNames "$readyToUse" -o go-template='{{ len .items }}' "$@"
}

delete_old_volumesnapshots() {
  local selector="${1##selector=}"
  local max_snapshots="${2##max_snapshots=}"

  while [ "$(getNumberOfSnapshots readyToUse=true --selector="$selector")" -gt "$max_snapshots" ]; do
    sleep 5
    NUMBER_OF_SNAPSHOTS=$(getNumberOfSnapshots readyToUse=true --selector="$selector")
    printf "%s Number of snapshots with selector '$selector' is too high at $NUMBER_OF_SNAPSHOTS. Deleting 1.\n" "$(timestamp)"
    SNAPSHOTS=$(getSnapshotNames readyToUse=true --selector="$selector")
    if ! kubectl delete volumesnapshots "${SNAPSHOTS%% *}" --namespace "${NAMESPACE}"; then
      printf "%s ERROR deleting snapshot. ${SNAPSHOTS%% *}\n" "$(timestamp)"
    fi
    sleep 10
  done
}

# delete_stuck_volumesnapshots() {
#   snapshot_list=$(kubectl get volumesnapshots -o jsonpath="{.items[*].metadata.name}")
#   arr=(`echo ${snapshot_list}`);
#   for snapshot_name in "${arr[@]}"; do
#     snapshot_creation_time_iso8601=$(kubectl get volumesnapshots $snapshot_name -o jsonpath='{.metadata.creationTimestamp}')
#     snapshot_creation_time_without_offset=${snapshot_creation_time_iso8601::-1}
#     snapshot_creation_time_unix=$(date -ud "$(echo $snapshot_creation_time_without_offset | sed 's/T/ /')" +%s)
#     current_date_unix=$(date -u +%s)
#     snapshot_age_minutes=$(( (current_date_unix - snapshot_creation_time_unix) / 60  ))
#     # Snapshots should never be older than 6 minutes
#     # If they are then there's a problem on AWS' end and the snapshot needs to be deleted.
#     if [ $snapshot_age_minutes -ge 6 ]; then
#       printf "%s Snasphot %s is %s minutes old.  It must be stuck. Attempting to delete...\n" "$(timestamp)" "$snapshot_name" "$snapshot_age_minutes"
#       err=$(kubectl delete volumesnapshots $snapshot_name 2>&1 > /dev/null)
#       if [ $? -ne 0 ]; then
#         printf "%s ERROR##### Unable to delete stuck snapshot %s .\n" "$(timestamp)" "$snapshot_name"
#         printf "%s Error was: \"%s\"\n" "$(timestamp)" "$err"
#         sleep 10
#         exit 1
#       else
#          printf "%s Successfully deleted stuck snapshot %s! \n" "$(timestamp)" "$snapshot_name"
#       fi
#     fi
#   done
# }

HISTORY_MODE="$(echo "$NODE_CONFIG" | jq -r ".history_mode")"
TARGET_VOLUME="$(echo "$NODE_CONFIG" | jq ".target_volume")"
PERSISTENT_VOLUME_CLAIM="$(
  kubectl get po -n "$NAMESPACE" -l node_class="$NODE_CLASS" \
    -o jsonpath="{.items[0].spec.volumes[?(@.name==$TARGET_VOLUME)].persistentVolumeClaim.claimName}"
)"

# For yq to work, the values resulting from the above cmds need to be exported.
# We don't export them inline because of
# https://github.com/koalaman/shellcheck/wiki/SC2155
export HISTORY_MODE
export PERSISTENT_VOLUME_CLAIM

yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml
yq e -i '.metadata.labels.history_mode=strenv(HISTORY_MODE)' createVolumeSnapshot.yaml
yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml
yq e -i '.spec.volumeSnapshotClassName=strenv(VOLUME_SNAPSHOT_CLASS)' createVolumeSnapshot.yaml

while true; do

  # Pause if nodes are not ready
  until [ "$(kubectl get pods -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -l appType=octez-node -l node_class_history_mode="${HISTORY_MODE}")" = "True" ]; do
    printf "%s Tezos node is not ready for snapshot.  Check node pod logs.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    until [ "$(kubectl get pods -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -l appType=octez-node -l node_class_history_mode="${HISTORY_MODE}")" = "True" ]; do
      sleep 1m # without sleep, this loop is a "busy wait". this sleep vastly reduces CPU usage while we wait for node
      if  [ "$(kubectl get pods -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -l appType=octez-node -l node_class_history_mode="${HISTORY_MODE}")" = "True" ]; then
        break
      fi
    done
  done

  # Remove unlabeled snapshots
  delete_old_volumesnapshots selector='!history_mode' max_snapshots=0
  # Maintain 4 snapshots of a certain history mode
  delete_old_volumesnapshots selector="history_mode=$HISTORY_MODE" max_snapshots=4
  # Check for and delete old stuck snapshots
  # delete_stuck_volumesnapshots

  if ! [ "$(getSnapshotNames readyToUse=false -l history_mode="${HISTORY_MODE}")" ]; then
    # EBS Snapshot name based on current time and date
    current_date=$(date "+%Y-%m-%d-%H-%M-%S" "$@")
    export SNAPSHOT_NAME="$current_date-$HISTORY_MODE-node-snapshot"
    # Update volume snapshot name
    yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

    printf "%s Creating snapshot ${SNAPSHOT_NAME} in ${NAMESPACE}.\n" "$(timestamp)"

    start_time=$(date +%s)

    # Create snapshot
    if ! kubectl apply -f createVolumeSnapshot.yaml; then
      printf "%s ERROR creating volumeSnapshot ${SNAPSHOT_NAME} in ${NAMESPACE} .\n" "$(timestamp)"
      exit 1
    fi

    sleep 5

    # While no snapshots ready
    while [ "$(getSnapshotNames readyToUse=false -l history_mode="${HISTORY_MODE}")" ]; do
      printf "%s Snapshot is still creating...\n" "$(timestamp)"
      sleep 10
      # delete_stuck_volumesnapshots
    done
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    printf "%s Snapshot ${SNAPSHOT_NAME} in ${NAMESPACE} finished." "$(timestamp)"
    eval "echo Elapsed time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')\n"
  else
    printf "%s Snapshot already in progress...\n" "$(timestamp)"
    sleep 10
    # delete_stuck_volumesnapshots
  fi

  printf "%s Sleeping for 10m due to Digital Ocean rate limit.\n" "$(timestamp)"
  sleep 10m  
done