# Public network node
Connecting to a public net is easy!

(See [here](https://tezos.gitlab.io/user/history_modes.html) for info on snapshots and node history modes)

Simply run the following to spin up a rolling history node:

```shell
helm install tezos-mainnet oxheadalpha/tezos-chain \
--namespace oxheadalpha --create-namespace
```

Running this results in:

- Creating a Helm [release](https://helm.sh/docs/intro/using_helm/#three-big-concepts) named tezos-mainnet for your k8s cluster.
- k8s will spin up one regular (i.e. non-baking node) which will download and import a mainnet snapshot. This will take a few minutes.
- Once the snapshot step is done, your node will be bootstrapped and syncing with mainnet!

You can find your node in the oxheadalpha namespace with some status information using `kubectl`.

```shell
kubectl -n oxheadalpha get pods -l appType=octez-node
```

You can monitor (and follow using the `-f` flag) the logs of the snapshot downloader/import container:

```shell
kubectl logs -n oxheadalpha statefulset/rolling-node -c snapshot-downloader -f
```

You can view logs for your node using the following command:

```shell
kubectl -n oxheadalpha logs -l appType=octez-node -c octez-node -f --prefix
```

IMPORTANT:

- Although spinning up a mainnet baker is possible, we do not recommend running a mainnet baker at this point in time. Secret keys should be handled via an HSM that should remain online, and the keys should be passed through a k8s secret to k8s. This functionality still needs to be implemented.
- You should be aware of `minikube` VM's allocated memory. Especially if you use `minikube` for other applications. It may run out of virtual memory say due to having large docker images. Being that snapshots are relatively large and increasing in size as the blockchain grows, when downloading one, you can potentially run out of disk space. The snapshot is deleted after import. According to `minikube start --help`, default allocated space is 20000mb. You can modify this via the `--disk-size` flag. To view the memory usage of the VM, you can ssh into `minikube`.

  ```shell
  ❯ minikube ssh
                          _             _
              _         _ ( )           ( )
    ___ ___  (_)  ___  (_)| |/')  _   _ | |_      __
  /' _ ` _ `\| |/' _ `\| || , <  ( ) ( )| '_`\  /'__`\
  | ( ) ( ) || || ( ) || || |\`\ | (_) || |_) )(  ___/
  (_) (_) (_)(_)(_) (_)(_)(_) (_)`\___/'(_,__/'`\____)

  $ df -h
  Filesystem      Size  Used Avail Use% Mounted on
  tmpfs           5.2G  593M  4.6G  12% /
  devtmpfs        2.8G     0  2.8G   0% /dev
  tmpfs           2.9G     0  2.9G   0% /dev/shm
  tmpfs           2.9G   50M  2.8G   2% /run
  tmpfs           2.9G     0  2.9G   0% /sys/fs/cgroup
  tmpfs           2.9G  8.0K  2.9G   1% /tmp
  /dev/vda1        17G   12G  4.2G  74% /mnt/vda1
  ```

