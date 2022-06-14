## Prerequisites

- python3 (>=3.7)
- [docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [helm](https://helm.sh/)
- (optional, for distributed private chains) A [ZeroTier](https://www.zerotier.com/) network with api access token

### For local deployment

- [minikube](https://minikube.sigs.k8s.io/docs/)

### For deployment on a cloud platform (AWS)

- we recommmend [pulumi](https://www.pulumi.com/docs/get-started/install/), an infrastructure-as-code platform, for cloud deployments

## Installing prerequisites

This section varies depending on OS.

### Mac

- Install [Docker Desktop](https://docs.docker.com/docker-for-mac/install/).

- Start Docker Desktop and follow the setup instructions. Note: You may quit Docker after it has finished setting up. It is not required that Docker Desktop is running for you to run a Tezos chain.

- Install [homebrew](https://brew.sh/):

  ```shell
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  ```

- Install other prerequisites:
  ```shell
  brew install python3 kubectl minikube helm
  ```

### Arch Linux

```shell
pacman -Syu && pacman -S docker python3 minikube kubectl kubectx helm
```

### Other Operating Systems

Please see the respective pages for installation instructions:

- [python3](https://www.python.org/downloads/)
- [docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [helm](https://helm.sh/docs/intro/install/)

## Configuring Minikube

It is suggested to deploy minikube as a virtual machine. This requires a virtual machine [driver](https://minikube.sigs.k8s.io/docs/drivers/).

### Mac

Requires the [hyperkit](https://minikube.sigs.k8s.io/docs/drivers/hyperkit/) driver. This comes already bundled together with Docker Desktop.

Make hyperkit the default minikube driver:

```shell
minikube config set driver hyperkit
```

(Note: We do not use Docker itself as the minikube driver due to an [issue](https://github.com/kubernetes/minikube/issues/7332) regarding the minikube ingress addon that is required by rpc-auth.)

### Other Operating Systems

If in the next step minikube does not start correctly, you may need to configure a different driver for it. Please see the minikube docs [here](https://minikube.sigs.k8s.io/docs/drivers/) for more information.

## Starting Minikube

```shell
minikube start
```

Configure your shell environment to use minikube’s Docker daemon:

```shell
eval $(minikube docker-env)
```

This allows you to run Docker commands inside of minikube. For example: `docker images` to view the images that minikube has.

If you want to unset your shell from using minikube's docker daemon:

```shell
eval $(minikube docker-env -u)
```

Add the Oxhead Alpha Helm chart repository to your local Helm installation:

```
helm repo add oxheadalpha https://oxheadalpha.github.io/tezos-helm-charts/
```
