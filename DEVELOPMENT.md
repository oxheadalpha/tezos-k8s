- [Helm Chart Development](#helm-chart-development)
  - [Prerequisites](#prerequisites)
- [Using devspace](#using-devspace)
  - [Notes](#notes)
- [Helm Charts](#helm-charts)
  - [Creating Charts](#creating-charts)
  - [Update charts for local mainnet](#update-charts-for-local-mainnet)
  - [Run charts for local mainnet](#run-charts-for-local-mainnet)
  - [Notes](#notes-1)
- [Creating Docker Images](#creating-docker-images)
- [Releases](#releases)

# Helm Chart Development

## Prerequisites

- Install [devspace](https://devspace.sh/cli/docs/introduction).

- Ensure minikube is running:

  ```shell
  minikube start
  ```

- Configure your shell to use minikube's docker daemon:

  ```shell
  eval $(minikube docker-env)
  ```

# Using devspace

- Tell devspace which namespace to use:

  ```shell
  devspace use namespace tqtezos
  ```

- Run `mkchain` to generate your Helm values. (Note: Devspace will only deploy `rpc-auth` if you use the `rpc-auth` profile, regardless if you set it in mkchain. This is to avoid devspace deployment issues. See more below.)

- Run `helm dependency update charts/tezos`. This grabs all the Tezos chart dependencies and packages them inside the chart's `charts/` directory. Currently this is just the `rpc-auth` chart. You'll need to run this for all charts that have dependencies in the future.

- Set a `CHAIN_NAME` env var.

- Run `devspace dev --var CHAIN_NAME=$CHAIN_NAME` (you can leave out the `--var` flag if you used `export CHAIN_NAME=my-chain`).

- You may add the `rpc-auth` devspace [profile](https://devspace.sh/cli/docs/configuration/profiles/basics) by using the `-p rpc-auth` flag in the `devspace dev` command. This tells devspace deploy `rpc-auth` and to redeploy it if its files change. You can also pass another `--var` flag for `rpc-auth` like so: `--var FLASK_ENV=<development|production>`. Devpsace defaults it to `development`. Running with `development` will allow the python server to hot reload on file changes. Devspace does not need to restart the pod on file changes as the python server file is [synced](https://devspace.sh/cli/docs/configuration/development/file-synchronization) to the container.

Devspace will now do a few things:

- Create namespace if it doesn't already exist.
- Runs a hook to enable the minikube nginx ingress addon. This is the gateway for external users to access the `rpc-auth` backend and to then make RPC calls to the Tezos node.
- Runs a hook to increase `fs.inotify.max_user_watches` to 1048576 in minikube. This is to avoid a "no space left on device" error. See [here](https://serverfault.com/questions/963529/minikube-k8s-kubectl-failed-to-watch-file-no-space-left-on-device) for more.
- Builds docker images and tags them.
- Deploys Helm charts.
- Starts [sync](https://devspace.sh/cli/docs/configuration/development/file-synchronization), [logging](https://devspace.sh/cli/docs/configuration/development/log-streaming), and [port-forwarding](https://devspace.sh/cli/docs/configuration/development/port-forwarding) services.
  - Right now just `rpc-auth` produces logs from the python server.
  - Port-forwarding allows you to directly communicate with containers, allowing for easy bootstrap node RPC calls, as well as requests to the `rpc-auth` server instead of having to go through the NGINX ingress. Example: `curl localhost:8732/chains/main/chain_id`
- Will automatically redeploy Helm charts and rebuild docker images depending upon the files you modify.

## Notes

- Devspace recommends to run [devspace purge](https://devspace.sh/cli/docs/commands/devspace_purge) to delete deployments. Keep in mind though that it currently does not delete persistent volumes and claims. They currently don't mention this in their docs. If you want to delete all resources including persistent volumes and claims, run `kubectl delete namespace <NAMESPACE>`. Even with this command, there are times where PV's/PVC's do not get deleted. This is important to know because you may be spinning up nodes that get old volumes attached with old state, and you may encounter Tezos pod errors. I have experienced this in situations where I left my cluster running for a long time, say overnight, and I shut my laptop and/or it went to sleep. After logging back in and deleting the namespace, the PV's/PVC's are still there and need to be manually deleted.

- If you would like to build all of our images without using Devspace to deploy (you might want to do a `helm install` instead), you can run `devspace build -t dev`.

- Due to a current limitation of devspace, multiple profiles cannot be used at one time. Therefore, devspace will watch `zerotier` files even if tezos nodes are not configured to use it via `mkchain`. Preferably `zerotier` would also be a profile in addition to `rpc-auth` being one.

- If you find that you have images built but Devspace is having a hard time getting them and/or is producing errors that don't seem to make sense, you can try `rm -rf .devspace` to remove any potentially wrong state.

# Helm Charts

## Creating Charts

The `version` in Chart.yaml should be `0.0.0`. This is what is stored in version control. The CI will update the version on release and store in our Helm chart repo.

Chart.yaml does not require an `appVersion`. So we are not using it as it doesn't make sense in our context being that our application is currently a monorepo and every component version is bumped as one. The `version` field is sufficient.

Regarding chart dependencies, Chart.yaml should not specify a dependency version for another _local_ chart.

Being that all charts are bumped to the same version on release, the parent chart will get the latest version of the dependency by default (which is the same as its own version) when installing via our Helm chart [repo](https://github.com/tqtezos/tezos-helm-charts).

## Update charts for local mainnet

```
helm dependency update charts/tezos
```

## Run charts for local mainnet

```
helm install tezos-mainnet charts/tezos --namespace tqtezos --create-namespace
```

## Notes

If you use `helm install|upgrade` (instead of devspace) for local charts, make sure you `helm dependency update <chart>` to get the latest local dependency chart changes that you've made packaged into the parent chart.

# Creating Docker Images

Currently, we are placing all docker images in the root level directory. The name of the folder is treated as the name of the image being created.

Here is an example of the flow for creating new images and how they are published to Docker Hub via the CI:

- You are creating a new image that you call `chain-initiator`. Name its folder `chain-initiator`. This folder should contain at least a `Dockerfile`.

- The CI on release will pre-pend `tezos-k8s` to the folder name, so `tezos-k8s-chain-initiator`. That is what the image will be named on Docker Hub under the `tqtezos` repo. So you would pull/push `tqtezos/tezos-k8s-chain-initiator`. All of our image names will have this format.

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
- Helm charts will be deployed to our Github Pages [repo](https://github.com/tqtezos/tezos-helm-charts)

See the Github CI file [./.github/workflows/ci.yml](.github/workflows/ci.yml) for our full CI pipeline.
