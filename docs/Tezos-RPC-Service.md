## RPC Authentication

You can optionally spin up an RPC authentication backend allowing trusted users to make RPC requests to your cluster.

Follow the steps at `rpc-auth/README.md`.

# Using a custom Tezos build

Create a clone of the `[tezos](https://gitlab.com/tezos/tezos)`
repository.  [Set up your development environment as usual](https://tezos.gitlab.io/introduction/howtoget.html#setting-up-the-development-environment-from-scratch).  Then run:

```shell
eval $(minikube docker-env)
make docker-image
```

This will create a docker image called `tezos:latest` and install it
into the minikube environment.

Or, if you prefer, you can build the image using:
```shell
./scripts/create_docker_image.sh
```

This will create an image with a name like `tezos/tezos:v13-rc1`.
Then you install it thus:
```shell
docker image save <image> | ( eval $(minikube docker-env); docker image load )
```

Either way, inside `$CHAIN_NAME_values.yaml`, change the `images` section to:

```yaml
images:
  octez: <image>
```

where image is `tezos:latest` or whatever.

Then install the chart as above.

