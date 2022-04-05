# Snapshot Warmer

For 1 Kubernetes Namespace this Helm Chart creates -

- 2 Kubernetes **Deployments**
- Kubernetes **Role**
- Kubernetes **Rolebinding**
- Kubernetes **Service** Account
- Kubernetes **ClusterRoleBinding**

This continuously takes AWS EBS Volume Snapshots of a Tezos-node and makes them available as Kubernetes VolumeSnapshots.

The reason for this is the longer you wait to take an EBS snapshot, the longer it takes to actually create the snapshot of an AWS EBS Volume.

If we continuously take snapshots, this assures that the artifact creation process does not have to wait for a snapshot to complete and also always has the newest data to work with.

## Dependencies & Testing

This Helm Chart is configured to work only with an AWS EKS cluster. It requires AWS IAM Roles and Policies, an AWS OIDC provider, and the EKS CSI driver to perform necessary actions on AWS resources from Kubernetes Pods.

Testing in minikube without AWS mocking tools is not possible. You should create your own EKS cluster to test.

## Setup

You should have 2 Tezos nodes deployed in your cluster. One with **archive** history mode, and the other with **rolling** history mode.
The `values.yaml` should reference these 2 nodes:

```yaml
# `nodes` contains the names of the nodes deployed. Each node specifies
# their `target_volume` to snapshot and their `history_mode`.
nodes:
  snapshot-archive-node:
    history_mode: archive
    target_volume: var-volume
  snapshot-rolling-node:
    history_mode: rolling
    target_volume: var-volume
```

## How it works

### Snapshot Warmer Deployment

This Kubernetes Deployment runs the `snapshot_maker` container located in the root of the `tezos-k8s` repository.

The entrypoint is overridden and the `snapshot-warmer/scripts/snapshotwarmer.sh` script is provided as the container entrypoint.

This script runs indefinitely and performs the following steps -

1. Removes unlabeled VolumeSnapshots. VolumeSnapshots need to be labeled with their respective `history_mode` in order for them to be used later with the snapshot engine system.
2. Maintains 4 snapshots of a particular `history_mode` label. There isn't any particular reason for this, other than to keep the list of snapshots concise. "Maintains" meaning deletes the oldest snapshots once the count is over 4.
3. If there are not any snapshots in progress, then a new one is triggered named with the current time and date.
4. It waits until the snapshot is ready to use.

We create only one snapshot at a time as having more than one in-progress slows down the snapshot process altogether.
