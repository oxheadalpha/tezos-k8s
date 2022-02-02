#!/bin/sh

cd /

ZIP_AND_UPLOAD_JOB_NAME=zip-and-upload-"${HISTORY_MODE}"

# Pause if nodes are not ready
while [ "$(kubectl get pods -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -l appType=tezos-node -l node_class_history_mode="${HISTORY_MODE}")" = "False" ]; do
    printf "%s Tezos node is not ready for snapshot.  Check node pod logs.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 30
done

# Delete zip-and-upload job
if kubectl get job "${ZIP_AND_UPLOAD_JOB_NAME}" --namespace "${NAMESPACE}"; then
    printf "%s Old zip-and-upload job exits.  Attempting to delete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if ! kubectl delete jobs "${ZIP_AND_UPLOAD_JOB_NAME}" --namespace "${NAMESPACE}"; then
            printf "%s Error deleting zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            exit 1
    fi
    printf "%s Old zip-and-upload job deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s No old zip-and-upload job detected for cleanup.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

# Delete old PVCs
if [ "${HISTORY_MODE}" = rolling ]; then
    if [ "$(kubectl get pvc rolling-tarball-restore --namespace "${NAMESPACE}")" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc rolling-tarball-restore --namespace "${NAMESPACE}"
    sleep 5
fi
fi

if [ "$(kubectl get pvc "${HISTORY_MODE}"-snapshot-cache-volume --namespace "${NAMESPACE}")" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc "${HISTORY_MODE}"-snapshot-cache-volume --namespace "${NAMESPACE}"
    sleep 5
fi

if [ "$(kubectl get pvc "${HISTORY_MODE}"-snap-volume --namespace "${NAMESPACE}")" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc "${HISTORY_MODE}"-snap-volume --namespace "${NAMESPACE}"
    sleep 5
fi


# Wait if there's a snapshot creating  or this snapshot will take extra long
# TODO use this snapshot once its done
while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")" ]; do
    printf "%s There is a snapshot currently creating... Paused until that snapshot is finished...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 30
done

SNAPSHOTS=$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==true)].metadata.name}' --namespace "${NAMESPACE}" -l history_mode="${HISTORY_MODE}")
NEWEST_SNAPSHOT=${SNAPSHOTS##* }

# Target node PVC for snapshot
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml


# Set namespace for both "${HISTORY_MODE}"-snapshot-cache-volume and rolling-tarball-restore
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' scratchVolume.yaml

# Create "${HISTORY_MODE}"-snapshot-cache-volume
printf "%s Creating PVC ${HISTORY_MODE}-snapshot-cache-volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
NAME="${HISTORY_MODE}-snapshot-cache-volume" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
if ! kubectl apply -f scratchVolume.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi


if [ "${HISTORY_MODE}" = rolling ]; then
    # Create rolling-tarball-restore
    printf "%s Creating PVC rolling-tarball-restore..\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    NAME="rolling-tarball-restore" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
    if ! kubectl apply -f scratchVolume.yaml
    then
        printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        exit 1
    fi
fi

## Snapshot volume namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' volumeFromSnap.yaml

## Snapshot volume name
VOLUME_NAME="${HISTORY_MODE}-snap-volume"
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.metadata.name=strenv(VOLUME_NAME)' volumeFromSnap.yaml

# Point snapshot PVC at snapshot
NEWEST_SNAPSHOT="${NEWEST_SNAPSHOT}" yq e -i '.spec.dataSource.name=strenv(NEWEST_SNAPSHOT)' volumeFromSnap.yaml

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



# Trigger subsequent filesytem inits, snapshots, tarballs, and uploads.
if ! kubectl apply -f mainJob.yaml
then
    printf "%s Error creating Zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi


i=1
while [ "$i" -ne 10 ]
do
    printf "%s Sleeping for %s seconds and waiting for job to create.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "${i}"
    sleep 1
    i=$((i + 1))
done




# Wait for snapshotting job to complete
while [ "$(kubectl get jobs "${ZIP_AND_UPLOAD_JOB_NAME}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; do
    if kubectl get pod -l job-name="${ZIP_AND_UPLOAD_JOB_NAME}" --namespace="${NAMESPACE}"| grep -i -e error -e evicted -e pending; then
        printf "%s Zip-and-upload job failed. This job will end and a new snapshot will be taken.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
        break
    else
        printf "%s Zip-and-upload job completed successfully.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    printf "%s Waiting for zip-and-upload job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
    sleep 5
done

# Delete snapshot PVC
printf "%s Deleting temporary snapshot volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
kubectl delete -f volumeFromSnap.yaml  | while IFS= read -r line; do printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "$line"; done

# Job deletes iself after its done
printf "%s Deleting this job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
JOB_NAME=snapshot-maker-"${HISTORY_MODE}"-node
kubectl delete job "${JOB_NAME}" --namespace "${NAMESPACE}"