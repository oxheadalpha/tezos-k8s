#!/bin/bash
source ./envs

# Snapshot values

## Snapshot class
VOLUME_SNAPSHOT_CLASS_NAME="${VOLUME_SNAPSHOT_CLASS_NAME}" yq e -i '.spec.volumeSnapshotClassName=strenv(VOLUME_SNAPSHOT_CLASS_NAME)' snapshot-maker/createVolumeSnapshot.yaml

## Role namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' rbac/role.yaml

## Rolebinding namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' rbac/rolebinding.yaml

## Rolebinding namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-scheduler.yaml

# Configmaps for jobs
kubectl create configmap snapshot-configmap --from-env-file=envs --namespace="${NAMESPACE}"

aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 082993323195.dkr.ecr.us-east-2.amazonaws.com

images=(
"snapshot-maker"
"zip-and-upload"
"snapshot-scheduler"
)

for image in "${images[@]}"
do
    aws ecr create-repository --repository-name "${image}"
    docker build -t "${image}" "${image}"/
    docker tag "${image}":latest 082993323195.dkr.ecr.us-east-2.amazonaws.com/"${image}":latest
    docker push 082993323195.dkr.ecr.us-east-2.amazonaws.com/"${image}":latest
done

kubectl apply -f rbac

eksctl create iamserviceaccount \
    --name snapshot-maker-sa \
    --namespace "${NAMESPACE}" \
    --cluster oxheadinfra-eksCluster-4751807 \
    --attach-policy-arn arn:aws:iam::082993323195:policy/snapshot-maker-ecr-read-s3-read \
    --approve \
    --override-existing-serviceaccounts

kubectl apply -f snapshot-scheduler.yaml