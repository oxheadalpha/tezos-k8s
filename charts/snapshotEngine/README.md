# Snapshot Engine

A Helm chart for creating Tezos filesystem artifacts for faster node sync. Check out [xtz-shots.io](xtz-shots.io) for an example.

- [Snapshot Engine](#snapshot-engine)
  - [What is it?](#what-is-it)
  - [Requirements](#requirements)
  - [How To](#how-to)
  - [Values](#values)
  - [Produced files](#produced-files)
    - [LZ4](#lz4)
    - [JSON](#json)
    - [Redirects](#redirects)
  - [Components](#components)
    - [Snapshot Warmer Deployment](#snapshot-warmer-deployment)
    - [Snapshot Scheduler Deployment](#snapshot-scheduler-deployment)
    - [Jobs](#jobs)
      - [Snapshot Maker Job](#snapshot-maker-job)
      - [Zip and Upload Job](#zip-and-upload-job)
    - [Containers](#containers)
      - [Docker & ECR](#docker--ecr)
      - [Kubernetes Containers](#kubernetes-containers)
        - [init-tezos-filesystem Container](#init-tezos-filesystem-container)
        - [create-tezos-rolling-snapshot Container](#create-tezos-rolling-snapshot-container)
        - [zip-and-upload Container](#zip-and-upload-container)

## What is it?

The Snapshot Engine is a Helm Chart to be deployed on a Kubernetes Cluster.  It will deploy snapshottable Tezos nodes [tezos-k8s](https://github.com/oxheadalpha/tezos-k8s) and produce Tezos `.rolling` snapshot files as well as a new archive and rolling finalized filesystem tarballs in LZ4 format for fast Tezos node syncing.

## Requirements

1. AWS EKS Cluster*
2. Docker
3. Optionally a remote container repository such as ECR*
4. S3 Bucket*
5. ECR Repo*
6. IAM Role* with a Trust Policy scoped to the Kubernetes Service Account created by this Helm chart.
7. [OIDC Provider](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)*
8. [Amazon EBS CSI Driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)*
9. [Kubernetes VolumeSnapshot CRDs, and a new Storage Class](https://aws.amazon.com/blogs/containers/using-ebs-snapshots-for-persistent-storage-with-your-eks-cluster/)

*&ast;We run our Tezos nodes on EKS.  It may be possible to deploy the Snapshot Engine on other Kubernetes Clusters at this time, but we have not tested these options.*

*&ast;We are hoping to make the Snapshot Engine cloud-agnostic, but for now AWS is required.*

## How To

1. Create an S3 Bucket.  

  :warning: If you want to make it available over the internet, you will need to make it a [Public Bucket](https://aws.amazon.com/premiumsupport/knowledge-center/read-access-objects-s3-bucket/) and with the following Bucket Policy.

  Replace  `BUCKET_NAME` with the name of your new S3 Bucket.

  :warning: Please evaluate in accordance with your own security policy. This will open up this bucket to the internet and allow anyone to download items from it and **you will incur AWS charges**.

  ```json
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "PublicReadGetObject",
              "Effect": "Allow",
              "Principal": "*",
              "Action": "s3:GetObject",
              "Resource": "arn:aws:s3:::<BUCKET_NAME>/*"
          }
      ]
  }
  ```

2. Create an IAM Role with the following statements.

  Replace `<ARN_OF_S3_BUCKET>` with the ARN of your new S3 Bucket.

  :warning: Pay close attention to the seemlingly redundant final `Resource` area. 

  `/` and `/*` provide permission to the root and contents of the S3 Bucket respectively. 

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": ["ec2:CreateSnapshot"],
        "Effect": "Allow",
        "Resource": "*"
      },
      {
        "Action": ["ec2:DescribeSnapshots"],
        "Effect": "Allow",
        "Resource": "*"
      },
      {
        "Action": ["s3:*"],
        "Effect": "Allow",
        "Resource": [
          "ARN_OF_S3_BUCKET",
          "ARN_OF_S3_BUCKET/*"
        ]
      }
     ]
    }
  ```

3. Scope this new IAM role with a Trust Policy with the following content:

:warning: You will need to update `SERVICE_ACCOUNT_NAMESPACE` with the name of Kubernetes namespace you will like your snapshottable Tezos nodes and Snapshot Engine chart to.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC_PROVIDER"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "OIDC_PROVIDER:sub": "system:serviceaccount:SERVICE_ACCOUNT_NAMESPACE:snapshot-engine-sa"
        }
      }
    }
  ]
}
```

4. Build the containers

You can build and push your images to a repo of your choosing, but this is how it can be done without automation to ECR with Docker. We recommend utilizing a configuration management tool to help with container orchestration such as Terraform or Pulumi.

```bash
# Get ECR login for Docker
aws ecr get-login-password --region YOUR_AWS_REGION | docker login --username AWS --password-stdin YOUR_ECR_URL

# Build the image with Docker
docker build -t snapshotEngine snapshotEngine/

# Tag the image. Will be used in values.yaml
docker tag snapshotEngine:latest YOUR_ECR_URL/snapshotEngine:latest

# Push the image to ECR
docker push YOUR_ECR_URL/snapshotEngine:latest
```

5. Add our Helm repository.

```bash
helm repo add oxheadalpha https://oxheadalpha.github.io/tezos-helm-charts/
```

6. Deploy the chart feeding in the ARN of the IAM role you created above inline, or as as value in a values.yaml file.

```bash
helm install snapshotEngine \
--set iam_role_arn="IAM_ROLE_ARN" \
--set tezos_k8s_images.snapshotEngine="YOUR_ECR_URL/snapshotEngine:latest"
```

OR

```bash
cat << EOF > values.yaml
iam_role_arn: "IAM_ROLE_ARN"
tezos_k8s_images:
  snapshotEngine: YOUR_ECR_URL/snapshotEngine:latest
EOF
helm install snapshotEngine -f values.yaml
```

7. Depending on the chain size (mainnet more time, testnet less time) you should have `LZ4` tarballs, and if you are deploying to a rolling node Tezos `.rolling` snapshots as well in your S3 bucket.

:warning: Testnet artifacts may appear in as soon as 20-30 minutes or less depending on the size of the chain.   Rolling mainnet artifacts will take a few hours, and mainnet archive tarballs could take up to 24 hours.

```bash
aws s3 ls s3://mainnet.xtz-shots.io
                           PRE assets/
2022-04-10 19:40:33          0 archive-tarball
2022-04-10 19:40:35          0 archive-tarball-metadata
2022-04-12 15:23:37     405077 base.json
2022-04-12 15:23:57        518 feed.xml
2022-04-12 15:23:57      11814 index.html
2022-04-04 21:13:08 3939264512 mainnet-2253544.rolling
2022-04-04 21:15:18        482 mainnet-2253544.rolling.json
2022-04-12 11:22:32 3744214343 tezos-mainnet-rolling-tarball-2274806.lz4
2022-04-12 11:23:51        493 tezos-mainnet-rolling-tarball-2274806.lz4.json
2022-04-12 15:23:39          0 rolling
2022-04-11 12:51:53          0 rolling-metadata
2022-04-12 15:21:52          0 rolling-tarball
2022-04-12 15:21:53          0 rolling-tarball-metadata
2022-04-05 11:45:06        497 tezos-mainnet-archive-tarball-2252528.lz4.json
2022-04-05 12:16:13 353204307636 tezos-mainnet-archive-tarball-2255459.lz4
```

## Values

```yaml
tezos_k8s_images:
  snapshotEngine: tezos-k8s-snapshot-maker:dev # Change to name of your snapshotEngine image with tag

iam_role_arn: "" # Change this to the ARN of your IAM role with permissions to S3 and VolumeSnapshots
service_account: snapshot-engine-sa # Keep or change if you like

nodes:
  snapshot-archive-node:
    history_mode: archive
    target_volume: var-volume
  snapshot-rolling-node:
    history_mode: rolling
    target_volume: var-volume

images:
  octez: tezos/tezos:v12.2 # Version of Tezos that you will run

snapshotMarkdownTemplateUrl: url_to_md_file # Url of markdown file that will be processed by jekyll and host links to your artifacts

volumeSnapClass: volumeSnapshotClassName_from_cluster # Name of a volumeSnapshotClass CRD that you will have created during the CSI/Snapshot Storage Class installation process in your cluster.
```

## Produced files

### LZ4

These are tarballs of the `/var/tezos/node` directory. They are validated for block finalization, zipped, and uploaded to your S3 bucket.

### JSON

These are metadata files containing information about the uploaded artifact. Every artifact has its own metadata file, as well as a `base.json` containing a list of all artifacts created.

### Redirects

There are 6 - 0 byte files that are uploaded as redirects. These files are updated in S3 to redirect to the latest artifact for each.

* rolling >> latest `.rolling` Tezos **rolling** snapshot file.
* rolling-tarball >> latest **rolling** `.lz4` tarball
* archive-tarball >> latest **archive** `.lz4` tarball
* rolling-metadata >> latest `.rolling.json` metadata file
* rolling-tarball-metadata >> latest **rolling** `.lz4.json` metadata file
* archive-tarball metadata >> latest **archive** `.lz4.json` metadata file

## Components

For 1 Kubernetes Namespace this Helm Chart creates -

- 2 Kubernetes **Deployment** per history mode. (4 Total)
- Kubernetes **Role**
- Kubernetes **Rolebinding**
- Kubernetes **Service** Account
- Kubernetes **ClusterRoleBinding**
- Kubernetes **Configmap**

### Snapshot Warmer Deployment

This Kubernetes Deployment runs the `snapshotEngine` container located in the root of the `tezos-k8s` repository.

The entrypoint is overridden and the `snapshot-warmer/scripts/snapshotwarmer.sh` script is provided as the container entrypoint.

This script runs indefinitely and performs the following steps -

1. Removes unlabeled VolumeSnapshots. VolumeSnapshots need to be labeled with their respective `history_mode` in order for them to be used later with the snapshot engine system.
2. Maintains 4 snapshots of a particular `history_mode` label. There isn't any particular reason for this, other than to keep the list of snapshots concise. "Maintains" meaning deletes the oldest snapshots once the count is over 4.
3. If there are not any snapshots in progress, then a new one is triggered named with the current time and date.
4. It waits until the snapshot is ready to use.

We create only one snapshot at a time as having more than one in-progress slows down the snapshot process altogether.

### Snapshot Scheduler Deployment

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

One container is used for all Kubernetes Jobs and Pods.  The Dockerfile is located in `tezos-k8s/snapshotEngine`.

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

`tezos-k8s/snapshotEngine/entrypoint.sh`

```sh
case "$CMD" in
  snapshot-scheduler)	exec /snapshot-scheduler.sh	"$@"	;;
  snapshot-maker)			exec /snapshot-maker.sh		"$@"	;;
  zip-and-upload)	exec /zip-and-upload.sh	"$@"	;;
esac
```

`tezos-k8s/snapshotEngine/snapshotMakerJob.yaml`

```yaml
      containers:
        - name: snapshot-maker
          ...
          args:
              - "snapshot-maker"
```

`tezos-k8s/snapshotEngine/mainJob.yaml`

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
20. Curls chain website page from chainWebsiteMarkdown
21. Build web page with Jekyll with curled Markdown and metadata files
22. Upload website files to S3
