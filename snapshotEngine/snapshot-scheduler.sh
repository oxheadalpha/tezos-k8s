#!/bin/sh

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshotMakerJob.yaml

SERVICE_ACCOUNT="${SERVICE_ACCOUNT}" yq e -i '.spec.template.spec.serviceAccountName=strenv(SERVICE_ACCOUNT)' snapshotMakerJob.yaml

#Snapshot-maker image set
IMAGE_NAME="${IMAGE_NAME}" yq e -i '.spec.template.spec.containers[0].image=strenv(IMAGE_NAME)' snapshotMakerJob.yaml

#History mode for maker job
HISTORY_MODE="${HISTORY_MODE}" yq e -i '.spec.template.spec.containers[0].env[0].value=strenv(HISTORY_MODE)' snapshotMakerJob.yaml

# Job for each node type
JOB_NAME=snapshot-maker-"${HISTORY_MODE}"-node
JOB_NAME="${JOB_NAME}" yq e -i '.metadata.name=strenv(JOB_NAME)' snapshotMakerJob.yaml

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

  # Job exists
  if [ "$(kubectl get jobs "${JOB_NAME}" --namespace "${NAMESPACE}")" ]; then
    printf "%s Snapshot-maker job exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if [ "$(kubectl get jobs "${JOB_NAME}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
      printf "%s Snapshot-maker job not complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      if [ "$(kubectl get jobs "${JOB_NAME}" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')" = "True" ]; then
          printf "%s Snapshot-maker job failed. Check Job pod logs for more information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
          exit 1
      fi
      printf "%s Waiting for snapshot-maker job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
      sleep 5
      if kubectl get pod -l job-name="${JOB_NAME}" --namespace="${NAMESPACE}"| grep -i -e error -e evicted; then
        printf "%s Snapshot-maker job error. Deleting and starting new job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if ! kubectl delete jobs "${JOB_NAME}" --namespace "${NAMESPACE}"; then
          printf "%s Error deleting snapshot-maker job.  Check pod logs.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
          exit 1
        fi 
      fi
    fi
  else
      printf "%s Snapshot-maker job does not exist.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      # If PVC exists bound with no jobs running delete the PVC
      if [ "$(kubectl get pvc "${NAMESPACE}"-snap-volume -o 'jsonpath={..status.phase}' --namespace "${NAMESPACE}")" = "Bound" ]; then
        printf "%s PVC Exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if [ "$(kubectl get jobs --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ] \
            && [ "$(kubectl get jobs --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
          printf "%s No jobs are running.  Deleting PVC.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
          kubectl delete pvc "${HISTORY_MODE}"-snap-volume --namespace "${NAMESPACE}"
          sleep 5
        fi
      fi
      printf "%s Ready for new snapshot-maker job.  Triggering job now.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      if ! kubectl apply -f snapshotMakerJob.yaml; then
        printf "%s Error creating snapshot-maker job.  Check pod logs for more information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
      fi  
      sleep 5
  fi  
done