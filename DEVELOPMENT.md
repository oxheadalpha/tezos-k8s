# How to develop on mkchain

Using mkchain on a non-release workdir requires building custom containers in your minikube docker context.

## Set up minikube and install custom containers

[Follow installation instructions](https://devspace.sh/cli/docs/introduction).

Ensure minikube is running:

``` shell
minikube start
```

Build all containers:

``` shell
devspace build --skip-push --tag=dev
```

# Develop with devspace
(This is all still being worked on! Things should become more clear with the introduction of Helm.)

## Deploy a chain and have devspace watch only k8s manifest:
- Generate constants (with or without Zerotier flags)
- `devspace dev --var=CHAIN_NAME="$CHAIN_NAME"`

## Deploy chain with Zerotier and also watch the ZT docker file:
- Generate constants with ZT flags
- Use zerotier profile: `devspace dev --var=CHAIN_NAME="$CHAIN_NAME" -p zerotier`
- You may leave out the profile flag if you don't want devspace to watch for zerotier file changes.

## RPC Auth backend
I've experimented with the idea of giving each service its own devspace.yaml. Inside RPC auth's devspace.yaml, it defines mkchain as a dependency which by running RPC auth devspace.yaml as the entrypoint, will also spin up mkchain (with zerotier if you generated it). Devspace is currently limited in that it will not reload dependencies if their files change. Therefore right now, the recommended way if you would like to view logs and/or have dependencies auto reload, is to run `devspace dev/logs` in multiple shells.

### Deploy RPC auth backend and watch its files:
- `cd ./docker/rpc-auth`
- `devspace dev --var=CHAIN_NAME="$CHAIN_NAME"`

## Misc
- If you would like to avoid passing `--var=CHAIN_NAME="$CHAIN_NAME"` to devspace, you can execute in your shell `export CHAIN_NAME=my_chain`.
- You can pass mkchain args like so: `devspace dev --var=CHAIN_NAME="$CHAIN_NAME" --var=MKCHAIN_ARGS="--number-of-nodes 2"`
