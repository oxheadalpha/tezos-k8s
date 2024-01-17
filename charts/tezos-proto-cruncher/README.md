# Tezos-proto-cruncher

This chart deploys a daemonset to perform a brute-force search
of a vanity protocol name.

It leverages this project:

https://github.com/tacoinfra/tz-proto-vanity

It runs in a daemonset and uploads matches to a bucket.

Thus you can run arbitrarily large k8s clusters for this purpose and the daemon will utilize all nodes to their full potential.

See values.yaml for details.
