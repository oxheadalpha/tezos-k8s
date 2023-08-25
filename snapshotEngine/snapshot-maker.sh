#!/bin/bash

cd /

ZIP_AND_UPLOAD_JOB_NAME=zip-and-upload-"${HISTORY_MODE}"

# Delete zip-and-upload job
if kubectl get job "${ZIP_AND_UPLOAD_JOB_NAME}"; then
    printf "%s Old zip-and-upload job exits.  Attempting to delete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if ! kubectl delete jobs "${ZIP_AND_UPLOAD_JOB_NAME}"; then
            printf "%s Error deleting zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            exit 1
    fi
    printf "%s Old zip-and-upload job deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s No old zip-and-upload job detected for cleanup.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

# Delete old PVCs
if [ "${HISTORY_MODE}" = rolling ]; then
    if [ "$(kubectl get pvc rolling-tarball-restore)" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 5
    kubectl delete pvc rolling-tarball-restore
    sleep 5
    fi
fi

if [ "$(kubectl get pvc "${HISTORY_MODE}"-snapshot-cache-volume)" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 5
    kubectl delete pvc "${HISTORY_MODE}"-snapshot-cache-volume
    sleep 5
fi

if [ "$(kubectl get pvc "${HISTORY_MODE}"-snap-volume)" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 5
    kubectl delete pvc "${HISTORY_MODE}"-snap-volume
    sleep 5
fi

# while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")" ]; do
#     printf "%s Snapshot already in progress...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
#     sleep 10
# done

printf "%s EBS Snapshot finished!\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' -l history_mode="${HISTORY_MODE}")
NEWEST_SNAPSHOT=${SNAPSHOTS##* }

printf "%s Latest snapshot is %s.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${NEWEST_SNAPSHOT}"

printf "%s Creating scratch volume for artifact processing...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# Set namespace for both "${HISTORY_MODE}"-snapshot-cache-volume
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' scratchVolume.yaml

# Set storage class for sratch volume yaml
STORAGE_CLASS="${STORAGE_CLASS}" yq e -i '.spec.storageClassName=strenv(STORAGE_CLASS)' scratchVolume.yaml

sleep 5

# Create "${HISTORY_MODE}"-snapshot-cache-volume
printf "%s Creating PVC ${HISTORY_MODE}-snapshot-cache-volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
NAME="${HISTORY_MODE}-snapshot-cache-volume" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
if ! kubectl apply -f scratchVolume.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

printf "%s PVC %s created.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${HISTORY_MODE}-snapshot-cache-volume"


if [ "${HISTORY_MODE}" = rolling ]; then
    sleep 5
    # Create rolling-tarball-restore
    printf "%s Creating PVC rolling-tarball-restore..\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    NAME="rolling-tarball-restore" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
    if ! kubectl apply -f scratchVolume.yaml
    then
        printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        exit 1
    fi
    printf "%s PVC %s created.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "rolling-tarball-restore"
fi

## Snapshot volume namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' volumeFromSnap.yaml

# Set storageclass for restored volume
STORAGE_CLASS="${STORAGE_CLASS}" yq e -i '.spec.storageClassName=strenv(STORAGE_CLASS)' volumeFromSnap.yaml

## Snapshot volume name
VOLUME_NAME="${HISTORY_MODE}-snap-volume"
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.metadata.name=strenv(VOLUME_NAME)' volumeFromSnap.yaml

# Point snapshot PVC at snapshot
NEWEST_SNAPSHOT="${NEWEST_SNAPSHOT}" yq e -i '.spec.dataSource.name=strenv(NEWEST_SNAPSHOT)' volumeFromSnap.yaml

printf "%s Calculating needed snapshot restore volume size.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
# Set size of snap volume to snapshot size plus 20% rounded up.
printf "%s Newest snapshot is %s.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${NEWEST_SNAPSHOT}"
SNAPSHOT_CONTENT=$(kubectl get volumesnapshot -n "${NAMESPACE}" "${NEWEST_SNAPSHOT}" -o jsonpath='{.status.boundVolumeSnapshotContentName}')
printf "%s Volumesnapshotcontent for %s is %s.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${NEWEST_SNAPSHOT}" "${SNAPSHOT_CONTENT}"
EBS_SNAPSHOT_RESTORE_SIZE=$(kubectl get volumesnapshotcontent "${SNAPSHOT_CONTENT}" -o jsonpath='{.status.restoreSize}')
printf "%s EBS Snapshot Restore Size is %s in bytes.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${EBS_SNAPSHOT_RESTORE_SIZE}"

printf "%s EBS Snapshot size is %s.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "$(echo "${EBS_SNAPSHOT_RESTORE_SIZE}" | awk '{print $1/1024/1024/1024 "GB"}')"

# size in bytes | + 20% | to GB | rounded up
RESTORE_VOLUME_SIZE=$(echo "${EBS_SNAPSHOT_RESTORE_SIZE}" | awk '{print $1*1.2}' | awk '{print $1/1024/1024/1024}' | awk '{print ($0-int($0)>0)?int($0)+1:int($0)}')

printf "%s We're rounding up and adding 20%% , volume size will be %sGB.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${RESTORE_VOLUME_SIZE}"

RESTORE_VOLUME_SIZE="${RESTORE_VOLUME_SIZE}Gi" yq e -i '.spec.resources.requests.storage=strenv(RESTORE_VOLUME_SIZE)' volumeFromSnap.yaml

sleep 5

printf "%s Creating volume from snapshot ${NEWEST_SNAPSHOT}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
if ! kubectl apply -f volumeFromSnap.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

# TODO Check for PVC
printf "%s PersistentVolumeClaim ${HISTORY_MODE}-snap-volume created successfully in namespace ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# set history mode for tezos init container
HISTORY_MODE="${HISTORY_MODE}" yq e -i '.spec.template.spec.initContainers[0].env[0].value=strenv(HISTORY_MODE)' mainJob.yaml

# set pvc name for tezos init container
PVC="${HISTORY_MODE}-snapshot-cache-volume"
MOUNT_PATH="/${PVC}"
MOUNT_PATH="${MOUNT_PATH}" yq e -i '.spec.template.spec.initContainers[0].volumeMounts[1].mountPath=strenv(MOUNT_PATH)' mainJob.yaml
PVC="${PVC}" yq e -i '.spec.template.spec.initContainers[0].volumeMounts[1].name=strenv(PVC)' mainJob.yaml

# set history mode for rolling snapshot container
HISTORY_MODE="${HISTORY_MODE}" yq e -i '.spec.template.spec.containers[0].env[0].value=strenv(HISTORY_MODE)' mainJob.yaml

# set pvc name for rolling snapshot container
MOUNT_PATH="${MOUNT_PATH}" yq e -i '.spec.template.spec.containers[0].volumeMounts[1].mountPath=strenv(MOUNT_PATH)' mainJob.yaml
PVC="${PVC}" yq e -i '.spec.template.spec.containers[0].volumeMounts[1].name=strenv(PVC)' mainJob.yaml

# set history mode for zip and upload container
HISTORY_MODE="${HISTORY_MODE}" yq e -i  '.spec.template.spec.containers[1].env[0].value=strenv(HISTORY_MODE)' mainJob.yaml

# set pvc for zip and upload
MOUNT_PATH="${MOUNT_PATH}" yq e -i '.spec.template.spec.containers[1].volumeMounts[1].mountPath=strenv(MOUNT_PATH)' mainJob.yaml
PVC="${PVC}" yq e -i '.spec.template.spec.containers[1].volumeMounts[1].name=strenv(PVC)' mainJob.yaml

# Set new PVC Name in snapshotting job
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.spec.template.spec.volumes[0].persistentVolumeClaim.claimName=strenv(VOLUME_NAME)' mainJob.yaml

# Set image name for zip and upload
IMAGE_NAME="${IMAGE_NAME}" yq e -i '.spec.template.spec.containers[1].image=strenv(IMAGE_NAME)' mainJob.yaml

## Zip job namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' mainJob.yaml

# name per node type
ZIP_AND_UPLOAD_JOB_NAME="${ZIP_AND_UPLOAD_JOB_NAME}" yq e -i '.metadata.name=strenv(ZIP_AND_UPLOAD_JOB_NAME)' mainJob.yaml

# Tezos image gets set in values.yaml in base of submod .images.octez
TEZOS_IMAGE="${TEZOS_IMAGE}" yq e -i '.spec.template.spec.initContainers[0].image=strenv(TEZOS_IMAGE)' mainJob.yaml
TEZOS_IMAGE="${TEZOS_IMAGE}" yq e -i '.spec.template.spec.containers[0].image=strenv(TEZOS_IMAGE)' mainJob.yaml

# target pvc for artifact processing for entire job
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.spec.template.spec.volumes[0].persistentVolumeClaim.claimName=strenv(VOLUME_NAME)' mainJob.yaml
PVC="${PVC}" yq e -i '.spec.template.spec.volumes[1].persistentVolumeClaim.claimName=strenv(PVC)' mainJob.yaml
PVC="${PVC}" yq e -i '.spec.template.spec.volumes[1].name=strenv(PVC)' mainJob.yaml

# Gets rid of rolling job-related containers and volume/mounts.
if [ "${HISTORY_MODE}" = archive ]; then
    # Removes create-tezos-rolling-snapshot container from entire job
    yq eval -i 'del(.spec.template.spec.containers[0])' mainJob.yaml
    # Removes rolling-tarball-restore volume from entire job (second to last volume)
    yq eval -i 'del(.spec.template.spec.volumes[2])' mainJob.yaml
    # Removes rolling-tarball-restore volumeMount from zip-and-upload container (second to last volume mount)
    yq eval -i "del(.spec.template.spec.containers[0].volumeMounts[2])" mainJob.yaml
fi

# # Switch alternate cloud provider secret name based on actual cloud provider
# if [[ -n "${CLOUD_PROVIDER}" ]]; then
#     # Need to account for dynamic volumes removed above. For example if not rolling node then rolling volume is deleted.
#     SECRET_NAME="${NAMESPACE}-secret"
#     # Index of zip-and-upload container changes depending on if rolling job or archive job
#     NUM_CONTAINERS=$(yq e '.spec.template.spec.containers | length' mainJob.yaml)
#     # Index of mounts also changes depending on history mode
#     NUM_CONTAINER_MOUNTS=$(yq e ".spec.template.spec.containers[$(( NUM_CONTAINERS - 1 ))].volumeMounts | length" mainJob.yaml )
#     # Secret volume mount is last item in list of volumeMounts for the zip and upload container
#     SECRET_NAME="${SECRET_NAME}" yq e -i ".spec.template.spec.containers[$(( NUM_CONTAINERS - 1 ))].volumeMounts[$(( NUM_CONTAINER_MOUNTS - 1 ))].name=strenv(SECRET_NAME)" mainJob.yaml
#     # Index of job volumes change depending on history mode
#     NUM_JOB_VOLUMES=$(yq e '.spec.template.spec.volumes | length' mainJob.yaml )
#     #  Setting job secret volume to value set by workflow
#     SECRET_NAME="${SECRET_NAME}" yq e -i ".spec.template.spec.volumes[$(( NUM_JOB_VOLUMES - 1 ))].name=strenv(SECRET_NAME)" mainJob.yaml
#     SECRET_NAME="${SECRET_NAME}" yq e -i ".spec.template.spec.volumes[$(( NUM_JOB_VOLUMES - 1 ))].secret.secretName=strenv(SECRET_NAME)" mainJob.yaml
# fi

# Service account to be used by entire zip-and-upload job.
SERVICE_ACCOUNT="${SERVICE_ACCOUNT}" yq e -i '.spec.template.spec.serviceAccountName=strenv(SERVICE_ACCOUNT)' mainJob.yaml

sleep 10

# Trigger subsequent filesystem inits, snapshots, tarballs, and uploads.
if ! kubectl apply -f mainJob.yaml
then
    printf "%s Error creating Zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

sleep 20

# Wait for snapshotting job to complete
while [ "$(kubectl get jobs "zip-and-upload-${HISTORY_MODE}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; do
    printf "%s Waiting for zip-and-upload job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
    while [ "$(kubectl get jobs "zip-and-upload-${HISTORY_MODE}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; do
        sleep 1m # without sleep, this loop is a "busy wait". this sleep vastly reduces CPU usage while we wait for job
        if [ "$(kubectl get pod -l job-name=zip-and-upload-"${HISTORY_MODE}" --namespace="${NAMESPACE}"| grep -i -e error -e evicted -e pending)" ] || \
        [ "$(kubectl get jobs  "zip-and-upload-${HISTORY_MODE}" --namespace="${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].type}')" ] ; then
            printf "%s Zip-and-upload job failed. This job will end and a new snapshot will be taken.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
            break 2
        fi
        if ! [ "$(kubectl get jobs "zip-and-upload-${HISTORY_MODE}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
            break
        fi
    done
done

if ! [ "$(kubectl get jobs "zip-and-upload-${HISTORY_MODE}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
    printf "%s Zip-and-upload job completed successfully.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

    # Delete zip-and-upload job
    if kubectl get job "${ZIP_AND_UPLOAD_JOB_NAME}"; then
        printf "%s Old zip-and-upload job exits.  Attempting to delete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if ! kubectl delete jobs "${ZIP_AND_UPLOAD_JOB_NAME}"; then
                printf "%s Error deleting zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
                exit 1
        fi
        printf "%s Old zip-and-upload job deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    else
        printf "%s No old zip-and-upload job detected for cleanup.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi

    # Delete old PVCs
    if [ "${HISTORY_MODE}" = rolling ]; then
        if [ "$(kubectl get pvc rolling-tarball-restore)" ]; then
        printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        sleep 5
        kubectl delete pvc rolling-tarball-restore
        sleep 5
        fi
    fi

    if [ "$(kubectl get pvc "${HISTORY_MODE}"-snapshot-cache-volume)" ]; then
        printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        sleep 5
        kubectl delete pvc "${HISTORY_MODE}"-snapshot-cache-volume
        sleep 5
    fi

    if [ "$(kubectl get pvc "${HISTORY_MODE}"-snap-volume)" ]; then
        printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        sleep 5
        kubectl delete pvc "${HISTORY_MODE}"-snap-volume
        sleep 5
    fi

    SLEEP_TIME=0m

    if [ "${HISTORY_MODE}" = "archive" ]; then
        SLEEP_TIME="${ARCHIVE_SLEEP_DELAY}"
        if [ "${ARCHIVE_SLEEP_DELAY}" != "0m" ]; then
            printf "%s artifactDelay.archive is set to %s sleeping...\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${ARCHIVE_SLEEP_DELAY}"
        fi
    elif [ "${HISTORY_MODE}" = "rolling" ]; then
        SLEEP_TIME="${ROLLING_SLEEP_DELAY}"
        if [ "${ROLLING_SLEEP_DELAY}" != "0m" ]; then
            printf "%s artifactDelay.rolling is set to %s sleeping...\n" "$(date "+%Y-%m-%d %H:%M:%S")" "${ROLLING_SLEEP_DELAY}"
        fi
    fi

    if [ "${SLEEP_TIME}" = "0m" ]; then
        printf "%s artifactDelay.HISTORY_MODE was not set! No delay...\n" "$(date "+%Y-%m-%d %H:%M:%S")"
    fi

    sleep "${SLEEP_TIME}"

fi

printf "%s Deleting temporary snapshot volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
sleep 5
kubectl delete -f volumeFromSnap.yaml  | while IFS= read -r line; do printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "$line"; done
sleep 5
kubectl delete job snapshot-maker --namespace "${NAMESPACE}"
