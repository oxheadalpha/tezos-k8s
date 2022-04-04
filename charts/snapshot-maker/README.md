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

# Snapshot Scheduler

This Helm chart creates:

* 2 Kubernetes **Deployments**
* 1 Kubernetes **Configmap**

This is the main workflow that handles the creation of Tezos tarballs, snapshots, and the website build for xtz-shots.io

## Dependencies & Testing

The Jobs and Pods triggered by this Helm chart are dependent on Kubernetes Service Accounts that depend on AWS IAM Roles, AWS OIDC Trust Policy, the AWS EKS CSI driver, and AWS IAM policy to perform actions on AWS resources from Kubernetes Pods.

This Helm Chart is dependent on the AWS EKS CSI driver to create Kubernetes custom resources (VolumeSnapshots and VolumeSnapshotContents) and facilitate the creation of AWS EC2 EBS Volume Snapshots.

Subsequent jobs and pods are dependent on AWS S3 buckets, AWS ACM Certificates, Route 53 DNS Records, and AWS Route 53 domains.

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

#### Snapshot Scheduler Deployment

A Kubernetes Deployment called the **Snapshot Scheduler** runs indefinitely triggering a new Kubernetes Job called **Snapshot Maker**.  

Snapshot Scheduler waits until the Snapshot Maker Job is gone to schedule a new job. This way there are snapshots constantly being created instead of running on a schedule.

### Jobs

Overview of Jobs triggered by the Snapshot Scheduler workflow.

#### Snapshot Maker Job

Triggered by Snapshot Scheduler Kubernetes Deployment.

Steps this Job performs -

1. Waits until targeted Tezos Node is ready and healthy in Kubernetes.
2. Deletes zip-and-upload job if it exists.  This cleans up errored jobs and completed jobs.
3. Deletes rolling tarball restore PVC.
4. Deletes snapshot cache PVC.
5. Deletes snapshot restore PVC.
6. Waits if a snapshot is currently being taken.
7. Uses latest completed snapshot to restore to new snapshot restore PVC.
8. Creates snapshot cache volume, where files go that we don't want to be included in artifacts.
9. Creates restore volume to match size of snapshot plus 20%.
10. Triggers Zip and Upload job that creates artifacts.
11. Waits until Zip and Upload job is finished, or exits upon error.
12. Once Zip and Upload is finished the snapshot restore volume is deleted and this Job deletes itself.

#### Zip and Upload Job

Triggered by Snapshot Maker Kubernetes Job.

This job initializes the Tezos storage that was restored to a new PVC, creates rolling Tezos snapshot if targeted Tezos Node is rolling history mode, then LZ4s and uploads artifacts to S3, and finally builds the xtz-shots website.

### Containers

Overview of containers built by Docker and stored in ECR as well as a description of the functionality of the containers in the Kubernetes Pods.

#### Docker & ECR

One container is used for all Kubernetes Jobs and Pods.  The Dockerfile is located in `tezos-k8s/snapshot_maker`.

Container is based on `jekyll` container.

Tools installed include -

* AWS v2 CLI
* jq
* yq
* kubectl
* jekyll (container base)
* curl
* bash

The different functionality is accomplished by `sh` scripts located in this directory, and supplied by `args` in the deployments and jobs via `entrypoint.sh` in the same directory.

`tezos-k8s/snapshot_maker/entrypoint.sh`

```sh
case "$CMD" in
  snapshot-scheduler)	exec /snapshot-scheduler.sh	"$@"	;;
  snapshot-maker)			exec /snapshot-maker.sh		"$@"	;;
  zip-and-upload)	exec /zip-and-upload.sh	"$@"	;;
esac
```

`tezos-k8s/snapshot_maker/snapshotMakerJob.yaml`

```yaml
      containers:
        - name: snapshot-maker
          ...
          args:
              - "snapshot-maker"
```

`tezos-k8s/snapshot_maker/mainJob.yaml`

```yaml
      containers:
        ...
        - name: zip-and-upload
          ...
          args:
              - "zip-and-upload"
          ...
```

Snapshot Maker Docker container is built and uploaded to ECR.

#### Kubernetes Containers

Overview of functionality of containers in Kubernetes Job Pods.

##### init-tezos-filesystem Container

In order for the storage to be imported sucessfully to a new node, the storage needs to be initialized by the `tezos-node` application.

This container performs the following steps -

1. Chowns the history-mode-snapshot-cache-volume to 100 so subsequent containers can access files created in them.
2. Sets a trap so that we can exit this container after 2 minutes.  `tezos-node` does not provide exit criteria if there is an error. Around 20%-40% of the time there will be an error because the EC2 instance would normally need to be shut down before an EBS snapshot is taken. With Kubernetes this is not possible, so we time the filesystem initialization and kill it if it takes longer than 2 minutes.
3. Runs a headless Tezos RPC endpoint to initialize the storage.
4. Waits until RPC is available.
5. Writes `BLOCK_HASH`, `BLOCK_HEIGHT`, and `BLOCK_TIME` for later use to snapshot cache.

##### create-tezos-rolling-snapshot Container

This container only exists for a rolling history mode workflow.

This container performs the following steps -

1. Chowns the history-mode-snapshot-cache-volume and rolling-tarball-restore volume to 100 so subsequent containers can access files created in them.
2. Gets network name from the namespace.
3. Performs a `tezos-node config init` on our restored snapshot storage.
4. Performs a `tezos-node snapshot export` to create the `.rolling` file to be uploaded later.
5. Restores this new snapshot to the `rolling-tarball-restore` PVC to later create the rolling tarball.
6. Creates a file to alert the next job that the rolling snapshot is currently being created and tells it to wait.

##### zip-and-upload Container

This container LZ4s the rolling, and artifact filesystems into tarballs, and uploads the tarballs and `.rolling` file to the AWS S3 bucket website.  Metadata is generated here and the website is built as well.

This container performs the following steps -

1. Downloads existing `base.json` metadata file if it exists, if not creates a new one. This contains all of the metadata for all artifacts ever created.
2. If archive artifact workflow `/var/tezos/node` is LZ4d for archive excluding sensitive files `identity.json`, and `peers.json`.
3. Archive tarball SHA256 is generated.
4. Archive tarball filesize is generated.
5. Metadata is added to `base.json` and uploaded.
6. Build artifact-specific metadata json file and upload it to AWS S3 Bucket.
7. Create and upload archive tarball redirect file. This forwards to the latest archive artifact. (EX. `mainnet.xtz-shots.io/archive-tarball >> mainnet.xtz-shots.io/tezos-mainnet-archive-tarball-203942.lz4`)
8. If rolling artifact workflow waits for `.rolling` snapshot to be created and restored to new PVC by previous container.
9. If rolling artifact workflow `/var/tezos/node` is LZ4d for archive excluding sensitive files `identity.json`, and `peers.json`.
10. Rolling tarball SHA256 is generated.
11. Rolling tarball filesize is generated.
12. Metadata is added to `base.json` and uploaded.
13. Build artifact-specific metadata json file and upload it to AWS S3 Bucket.
14. Create and upload rolling tarball redirect file. This forwards to the latest archive artifact. (EX. `mainnet.xtz-shots.io/rolling-tarball >> mainnet.xtz-shots.io/tezos-mainnet-rolling-tarball-203942.lz4`)
15. Upload `.rolling` file to S3 AWS bucket.
16. Generate filesize, and SHA256 sum of `.rolling` file.
17. Add metadata to `base.json` and upload.
18. Add metadata to artifact-specific json and upload.
19. Get metadata from artifact json files (curl) for web page.
20. Build web page with Jekyll
21. Upload website files to S3
