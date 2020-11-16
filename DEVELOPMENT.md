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

