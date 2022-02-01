#!/bin/sh

cd /

## Snapshot Namespace
NAMESPACE="${NAMESPACE}" yq e -i '.metadata.namespace=strenv(NAMESPACE)' snapshotMakerJob.yaml

#Snapshot-maker image set
IMAGE_NAME="${IMAGE_NAME}" yq e -i '.spec.template.spec.containers[0].image=strenv(IMAGE_NAME)' snapshotMakerJob.yaml

#History mode for maker job
HISTORY_MODE="${HISTORY_MODE}" yq e -i '.spec.template.spec.containers[0].env[0].value=strenv(HISTORY_MODE)' snapshotMakerJob.yaml

while true; do
  # Job exists
  if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}")" ]; then
    printf "%s Snapshot-maker job exists.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
    if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" != "True" ]; then
      printf "%s Snapshot-maker job not complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
      if [ "$(kubectl get jobs "snapshot-maker" --namespace "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}')" = "True" ]; then
          printf "%s Snapshot-maker job failed. Check Job pod logs for more information.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")" 
          exit 1
      fi
      printf "%s Waiting for snapshot-maker job to complete.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"    
      sleep 60
      if kubectl get pod -l job-name=snapshot-maker --namespace="${NAMESPACE}"| grep -i -e error -e evicted; then
        printf "%s Snapshot-maker job error. Deleting and starting new job.\n" "$(date "+%Y-%m-%d %H:%M:%S" "$@")"
        if ! kubectl delete jobs snapshot-maker --namespace "${NAMESPACE}"; then
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
          kubectl delete pvc "${NAMESPACE}"-snap-volume --namespace "${NAMESPACE}"
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