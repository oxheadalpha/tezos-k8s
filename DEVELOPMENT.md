# Helm Chart Development

Using mkchain on a non-release workdir requires building custom containers in your minikube docker context.

## Set up minikube and install custom containers

Install [devspace](https://devspace.sh/cli/docs/introduction).

Ensure minikube is running:

```shell
minikube start
```

Build all containers:

```shell
devspace build --skip-push --tag=dev -p rpc-auth
```

The `-p rpc-auth` flag applies the optional `rpc-auth` backend to devspace and will also build the image in the above command. The `-p` flag is a devspace [profile](https://devspace.sh/cli/docs/configuration/profiles/basics).

# Using devspace

- Tell devspace which namespace to use:

  ```shell
  devspace use namespace tqtezos
  ```

- Run `mkchain` to generate your Helm values.

- Run `helm dependency update charts/tezos`. This grabs all the Tezos chart dependencies and packages them inside the chart's `charts/` directory. Currently this is just the `rpc-auth` chart.

- Set a `CHAIN_NAME` env var.

- Run `devspace dev --var CHAIN_NAME=$CHAIN_NAME` (you can leave out the `--var` flag if you used `export CHAIN_NAME=my_chain`).

- You may add the `rpc-auth` devspace profile by using the `-p rpc-auth` flag in the `devspace dev` command. This tells devspace to redeploy the `rpc-auth` backend if its files change. You can also pass another `--var` flag for `rpc-auth` like so: `--var FLASK_ENV=<development|production>`. Devpsace defaults it to `development`. Running with `development` will allow the the python server to reload on file changes. Devspace does not need to restart the pod on file changes as the python server file is [synced](https://devspace.sh/cli/docs/configuration/development/file-synchronization) to the container and allows for hot reloading.

Devspace will now do a few things:

- Runs a hook to enable the minikube nginx ingress addon. This is currently required for the `rpc-auth` backend to work.
- Runs a hook to increase `fs.inotify.max_user_watches` to 1048576 in minikube. This is to avoid a "no space left on device" error. See [here](https://serverfault.com/questions/963529/minikube-k8s-kubectl-failed-to-watch-file-no-space-left-on-device) for more.
- Builds docker images if needed.
- Deploys Helm charts
- Starts sync and port-forwarding services. Will also start logs for configured deployments. Right now this is is just for `rpc-auth`.
- Will automatically redeploy Helm charts and rebuild docker images depending upon the files you modify.


# Notes
- Due to a current limitation of devspace, multiple profiles cannot be used at one time. Therefore, devspace will watch `zerotier` files even if tezos nodes are not configured to use it via `mkchain`. Preferably `zerotier` would also be a profile in addition to `rpc-auth` being one.
- `rpc-auth` will be deployed if configured via `mkchain`. Devspace will _not_ watch `rpc-auth` files however if you did not run `devspace dev` with the profile flag `-p rpc-auth`.
