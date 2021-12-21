#!/bin/bash
source ./envs

# Snapshot values

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-maker/createVolumeSnapshot.yaml
## Snapshot volume namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-maker/volumeFromSnap.yaml
## Zip job namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-maker/job.yaml

NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-scheduler.yaml

## Snapshot class
VOLUME_SNAPSHOT_CLASS_NAME="${VOLUME_SNAPSHOT_CLASS_NAME}" yq e -i '.spec.volumeSnapshotClassName=strenv(VOLUME_SNAPSHOT_CLASS_NAME)' snapshot-maker/createVolumeSnapshot.yaml

## Target volume name
PERSISTENT_VOLUME_CLAIM="${PERSISTENT_VOLUME_CLAIM}" yq e -i '.spec.source.persistentVolumeClaimName=strenv(PERSISTENT_VOLUME_CLAIM)' snapshot-maker/createVolumeSnapshot.yaml

# Snapshot Volume values

## Snapshot volume name
VOLUME_NAME="${NAMESPACE}-snap-volume" yq e -i '.metadata.name=strenv(VOLUME_NAME)' snapshot-maker/volumeFromSnap.yaml

# Cronjob values

## Cronjob namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' cronJob.yaml

## Cronjob name
NAME="${NAMESPACE}-snapshot-maker" yq e -i '.metadata.name=strenv(NAME)' cronJob.yaml

# Zip job values

## Zip job namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-maker/job.yaml

## Role namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' rbac/role.yaml

## Rolebinding namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' rbac/rolebinding.yaml

# Configmaps for jobs
kubectl create configmap snapshot-configmap --from-env-file=envs --namespace="${NAMESPACE}"
#kubectl create configmap init --from-file=snapshot-maker/init.sh --namespace="${NAMESPACE}"

aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 082993323195.dkr.ecr.us-east-2.amazonaws.com

docker build -t snapshot-maker snapshot-maker/
docker build -t zip-and-upload zip-and-upload/
#docker build -t tezos-snapshots tezos-snapshots/

docker tag snapshot-maker:latest 082993323195.dkr.ecr.us-east-2.amazonaws.com/snapshot-maker:latest
docker tag zip-and-upload:latest 082993323195.dkr.ecr.us-east-2.amazonaws.com/zip-and-upload:latest
#docker tag tezos-snapshots :latest 082993323195.dkr.ecr.us-east-2.amazonaws.com/tezos-snapshots :latest

docker push 082993323195.dkr.ecr.us-east-2.amazonaws.com/snapshot-maker:latest
docker push 082993323195.dkr.ecr.us-east-2.amazonaws.com/zip-and-upload:latest

kubectl apply -f rbac

kubectl apply -f cronJob.yaml

eksctl create iamserviceaccount \
    --name snapshot-maker-sa \
    --namespace "${NAMESPACE}" \
    --cluster oxheadinfra-eksCluster-4751807 \
    --attach-policy-arn arn:aws:iam::082993323195:policy/snapshot-maker-ecr-read-s3-read \
    --approve \
    --override-existing-serviceaccounts

## Trigger cronjob immediately
kubectl create job --from=cronjob/"${NAMESPACE}"-snapshot-maker snapshot-maker --namespace "${NAMESPACE}"

#sleep 5

#
#kubectl logs -n "${NAMESPACE}" -f --selector=app=snapshot-maker