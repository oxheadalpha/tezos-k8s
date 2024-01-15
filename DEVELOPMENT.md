- [Helm Chart Development](#helm-chart-development)
  - [Prerequisites](#prerequisites)
- [Helm Charts](#helm-charts)
  - [Creating Charts](#creating-charts)
  - [Run local development chart](#run-local-development-chart)
- [Creating Docker Images](#creating-docker-images)
- [Releases](#releases)

# Helm Chart Development

## Prerequisites

- Ensure minikube is running:

  ```shell
  minikube start
  ```

- Configure your shell to use minikube's docker daemon:

  ```shell
  eval $(minikube docker-env)
  ```

# Helm Charts

## Creating Charts

The `version` in Chart.yaml should be `0.0.0`. This is what is stored in version control. The CI will update the version on release and store in our Helm chart repo.

Chart.yaml does not require an `appVersion`. So we are not using it as it doesn't make sense in our context being that our application is currently a monorepo and every component version is bumped as one. The `version` field is sufficient.

Regarding chart dependencies, Chart.yaml should not specify a dependency version for another _local_ chart.

Being that all charts are bumped to the same version on release, the parent chart will get the latest version of the dependency by default (which is the same as its own version) when installing via our Helm chart [repo](https://github.com/oxheadalpha/tezos-helm-charts).

## Run local development chart

Instructions as per README install the latest release of tezos-k8s helm chart from a helm repository. To install a development version of a tezos chart in the charts/tezos directory instead, run:

```
helm install tezos-mainnet charts/tezos --namespace oxheadalpha --create-namespace
```

# Creating Docker Images

Currently, we are placing all docker images in the root level directory. The name of the folder is treated as the name of the image being created.

Here is an example of the flow for creating new images and how they are published to Docker Hub via the CI:

- You are creating a new image that you call `chain-initiator`. Name its folder `chain-initiator`. This folder should contain at least a `Dockerfile`.

- The CI on release will pre-pend `tezos-k8s` to the folder name, so `tezos-k8s-chain-initiator`. That is what the image will be named on Docker Hub under the `oxheadalpha` repo. So you would pull/push `oxheadalpha/tezos-k8s-chain-initiator`. All of our image names will have this format.

- In Helm charts that will be using the new image, set in the `values.yaml` file under the field `tezos_k8s_images` the value of `tezos-k8s-chain-initiator:dev`. (Any other images that a chart uses that it just pulls from a remote registry should go under the `images` field.) This is how the file will be stored in version control. On releases, the CI will set the tags to the release version and publish that to Docker Hub.

- When adding an image to Devspace, the image name needs to be the same as it is in `values.yaml`, i.e. `tezos-k8s-chain-initiator`. It does not need to be tagged because Devspace will add its own tag.
  Example:
  ```yaml
  images:
    chain-initiator:
      image: tezos-k8s-chain-initiator
      dockerfile: ./chain-initiator/Dockerfile
      context: ./chain-initiator
  ```

# Releases

Upon release, every component of the tezos-k8s repo will be bumped to that version. This is regardless if there were changes or not to that particular component. This is because tezos-k8s is a monorepo and we'd like to keep the versions consistent across the different components.

- mkchain will be published to pypi
- Docker images will be deployed to Docker Hub
- Helm charts will be deployed to our Github Pages [repo](https://github.com/oxheadalpha/tezos-helm-charts)

See the Github CI file [./.github/workflows/ci.yml](.github/workflows/ci.yml) for our full CI pipeline.
