# Snapshot Warmer

For 1 Kubernetes Namespace this Helm Chart creates -

* 2 Kubernetes **Deployments**
* Kubernetes **Role**
* Kubernetes **Rolebinding**
* Kubernetes **Service** Account
* Kubernetes **ClusterRoleBinding**

This continuously takes AWS EBS Volume Snapshots of a Tezos-node and makes them available as Kubernetes VolumeSnapshots.

The reason for this is the longer you wait to take an EBS snapshot, the longer it takes to actually create the snapshot of an AWS EBS Volume.  

If we continuously take snapshots, this assures that the artifact creation process does not have to wait for a snapshot to complete and also always has the newest data to work with.

## Dependencies & Testing

This Helm Chart is dependent on AWS IAM Roles, AWS OIDC Trust Policy, the AWS EKS CSI driver, and AWS IAM policy to perform actions on AWS resources from Kubernetes Pods.

All of these resources can be deployed to a real AWS EKS cluster with https://github.com/oxheadalpha/oxheadinfra. However testing in minikube without AWS mocking tools would not be possible.

## Setup

If your `values.yaml` needs at least 2 Tezos nodes, 1 with **archive** history mode, and another **rolling** history mode.

```yaml
nodes:
  rolling-node: null
  snapshot-archive-node:
  ... 
    instances:
      - ...
        config:
          shell:
            history_mode: archive
      - ...
  snapshot-rolling-node:
  ...
    instances:
      - ...
        config:
          shell:
            history_mode: rolling
      - ...
```

The Helm template loops over **the first** in each type array `snapshot-archive-node` and `snapshot-rolling-node`. If you have multiple rolling/archive nodes only the first one of each type is targeted by the snapshot scheduler.

No additonal values are required other than those required by Tezos-K8s itself.

Deploy with https://github.com/oxheadalpha/oxheadinfra

## How it works

Overview of the Snapshot Scheduler workflow.

### Deployments

Overview of Kubernetes Deployments created by this workflow.

#### Snapshot Warmer Deployment

This Kubernetes Deployment runs the `snapshot_maker` container located in the root of the `tezos-k8s` repository.

The entrypoint is overridden and the `snapshot-warmer/scripts/snapshotwarmer.sh` script is provided a the container entrypoint.

This script runs indefinitely and performs the following steps -

1. Removes unlabeled VolumeSnapshots. VolumeSnapshots need to be labeled with their respective `history mode` in order for them to be used later with the snapshot engine system.
2. Maintains 4 snapshots of a particular `history mode` label.  There isn't any particular reason for this, other than to keep the list of snapshots concise.  "Maintains" meaning deletes the oldest snapshots once the count is over 4.
3. If there are not any snapshots in progress, then a new one is triggered named with the current time and date.
4. It waits until the snapshot is ready to use.

The script will detect a snapshot in progress and wait if it is started if a snapshot is currently creating. This is to prevent runaway snapshot creation as more in-progress snapshots slows down the process altogether. We keep it to 1 at a time for optimal speed.
