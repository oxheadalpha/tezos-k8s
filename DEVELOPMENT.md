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

- Run `helm dependency update charts/tezos`. This grabs all the Tezos chart dependencies and packages them inside the chart's `charts/` directory. Currently this is just the `rpc-auth` chart.

- Set a `CHAIN_NAME` env var.

- Run `devspace dev --var CHAIN_NAME=$CHAIN_NAME` (you can leave out the `--var` flag if you used `export CHAIN_NAME=my_chain`).

- You may add the `rpc-auth` devspace [profile](https://devspace.sh/cli/docs/configuration/profiles/basics) by using the `-p rpc-auth` flag in the `devspace dev` command. This tells devspace deploy `rpc-auth` and to redeploy it if its files change. You can also pass another `--var` flag for `rpc-auth` like so: `--var FLASK_ENV=<development|production>`. Devpsace defaults it to `development`. Running with `development` will allow the the python server to hot reload on file changes. Devspace does not need to restart the pod on file changes as the python server file is [synced](https://devspace.sh/cli/docs/configuration/development/file-synchronization) to the container.

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


# Notes
- Due to a current limitation of devspace, multiple profiles cannot be used at one time. Therefore, devspace will watch `zerotier` files even if tezos nodes are not configured to use it via `mkchain`. Preferably `zerotier` would also be a profile in addition to `rpc-auth` being one.
