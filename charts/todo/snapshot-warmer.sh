#!/bin/bash
source ./envs

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshot-warmer.yaml

kubectl apply -f snapshot-warmer.yaml