#!/bin/sh

cd /

# Pause if nodes are not ready
while [ "$(kubectl get pods -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}' -l appType=tezos-node -l node_class_history_mode="${HISTORY_MODE}")" = "False" ]; do
    printf "%s Tezos node is not ready for snapshot.  Check node pod logs.  \n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 30
done

# Delete zip-and-upload job
if kubectl get job zip-and-upload --namespace "${NAMESPACE}"; then
    printf "%s Old zip-and-upload job exits.  Attempting to delete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if ! kubectl delete jobs zip-and-upload --namespace "${NAMESPACE}"; then
            printf "%s Error deleting zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
            exit 1
    fi
    printf "%s Old zip-and-upload job deleted.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
else
    printf "%s No old zip-and-upload job detected for cleanup.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
fi

# Delete old PVCs
if [ "$(kubectl get pvc rolling-tarball-restore -o 'jsonpath={..status.phase}' --namespace "${NAMESPACE}")" = "Bound" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc rolling-tarball-restore --namespace "${NAMESPACE}"
    sleep 5
fi

if [ "$(kubectl get pvc snapshot-cache-volume -o 'jsonpath={..status.phase}' --namespace "${NAMESPACE}")" = "Bound" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc snapshot-cache-volume --namespace "${NAMESPACE}"
    sleep 5
fi

if [ "$(kubectl get pvc "${NAMESPACE}"-snap-volume -o 'jsonpath={..status.phase}' --namespace "${NAMESPACE}")" = "Bound" ]; then
    printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    kubectl delete pvc "${NAMESPACE}"-snap-volume --namespace "${NAMESPACE}"
    sleep 5
fi


# Wait if there's a snapshot creating  or this snapshot will take extra long
# TODO use this snapshot once its done
while [ "$(kubectl get volumesnapshots -o jsonpath='{.items[?(.status.readyToUse==false)].metadata.name}' --namespace "${NAMESPACE}")" ]; do
    printf "%s There is a snapshot currently creating... Paused until that snapshot is finished...\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 30
done

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' createVolumeSnapshot.yaml

# EBS Snapshot name based on current time and date
SNAPSHOT_NAME=$(date "+%Y-%m-%d-%H-%M-%S" "$@")-"${HISTORY_MODE}"-node-snapshot

# Update snapshot name
SNAPSHOT_NAME="${SNAPSHOT_NAME}" yq e -i '.metadata.name=strenv(SNAPSHOT_NAME)' createVolumeSnapshot.yaml

# Target node PVC for snapshot
PERSISTENT_VOLUME_CLAIM=var-volume-snapshot-"${HISTORY_MODE}"-node-0
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' createVolumeSnapshot.yaml

# Create snapshot
if ! kubectl apply -f createVolumeSnapshot.yaml
then
    printf "%s Error creating volumeSnapshot ${SNAPSHOT_NAME}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

# Wait for snapshot to complete
while [ "$(kubectl get volumesnapshot "${SNAPSHOT_NAME}" -n "${NAMESPACE}" --template="{{.status.readyToUse}}")" != "true" ]; do
    printf "%s Waiting for snapshot creation to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    sleep 15
done

printf "%s VolumeSnapshot ${SNAPSHOT_NAME} created successfully in namespace ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# Set namespace for both snapshot-cache-volume and rolling-tarball-restore
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' scratchVolume.yaml

# Create snapshot-cache-volume
printf "%s Creating PVC snapshot-cache-volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
NAME="snapshot-cache-volume" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
if ! kubectl apply -f scratchVolume.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

# Create rolling-tarball-restore
printf "%s Creating PVC rolling-tarball-restore..\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
NAME="rolling-tarball-restore" yq e -i '.metadata.name=strenv(NAME)' scratchVolume.yaml
if ! kubectl apply -f scratchVolume.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

## Snapshot volume namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' volumeFromSnap.yaml

## Snapshot volume name
VOLUME_NAME="${NAMESPACE}-snap-volume"
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.metadata.name=strenv(VOLUME_NAME)' volumeFromSnap.yaml

# Point snapshot PVC at snapshot
SNAPSHOT_NAME="${SNAPSHOT_NAME}" yq e -i '.spec.dataSource.name=strenv(SNAPSHOT_NAME)' volumeFromSnap.yaml

printf "%s Creating volume from snapshot ${SNAPSHOT_NAME}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
if ! kubectl apply -f volumeFromSnap.yaml
then
    printf "%s Error creating persistentVolumeClaim or persistentVolume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

# TODO Check for PVC
printf "%s PersistentVolumeClaim ${NAMESPACE}-snap-volume created successfully in namespace ${NAMESPACE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# Set new PVC Name in snapshotting job
VOLUME_NAME="${VOLUME_NAME}" yq e -i '.spec.template.spec.volumes[0].persistentVolumeClaim.claimName=strenv(VOLUME_NAME)' mainJob.yaml

# Set image name for zip and upload
IMAGE_NAME="${IMAGE_NAME}" yq e -i '.spec.template.spec.containers[1].image=strenv(IMAGE_NAME)' mainJob.yaml

## Zip job namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' mainJob.yaml


# DEBUG

printf "TEZOS_IMAGE env var is %s" "${TEZOS_IMAGE}"

TEZOS_IMAGE="${TEZOS_IMAGE}" yq e -i '.spec.template.spec.initContainers[0].image=strenv(TEZOS_IMAGE)' mainJob.yaml

# DEBUG
IMAGE=$(yq e '.spec.template.spec.initContainers[0].image' mainJob.yaml)
printf "%s Image set to ${IMAGE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"

# DEBUG
printf "TEZOS_IMAGE env var is %s" "${TEZOS_IMAGE}"

TEZOS_IMAGE="${TEZOS_IMAGE}" yq e -i '.spec.template.spec.containers[0].image=strenv(TEZOS_IMAGE)' mainJob.yaml

# DEBUG
IMAGE=$(yq e '.spec.template.spec.containers[0].image' mainJob.yaml)
printf "%s Image set to ${IMAGE}.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"


# Trigger subsequent filesytem inits, snapshots, tarballs, and uploads.
if ! kubectl apply -f mainJob.yaml
then
    printf "%s Error creating Zip-and-upload job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    exit 1
fi

# Wait for snapshotting job to complete
while [ "$(kubectl get jobs "zip-and-upload" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; do
    if kubectl get pod -l job-name=zip-and-upload --namespace="${NAMESPACE}"| grep -i -e error -e evicted; then
        printf "%s Zip-and-upload job failed. This job will end and a new snapshot will be taken.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
        printf "%s Deleting temporary snapshot volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        break
    else
        printf "%s Zip-and-upload job completed successfully.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        printf "%s Deleting temporary snapshot volume.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    fi
    printf "%s Waiting for zip-and-upload job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
    sleep 60
done

# Delete snapshot PVC
kubectl delete -f volumeFromSnap.yaml  | while IFS= read -r line; do printf '%s %s\n' "$(date "+%Y-%m-%d %H:%M:%S" "$@")" "$line"; done

# Job deletes iself after its done
kubectl delete job snapshot-maker --namespace "${NAMESPACE}"