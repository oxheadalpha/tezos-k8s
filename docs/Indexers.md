# Indexers

You can optionally spin up a Tezos blockchain indexer that makes querying for information very quick. An indexer puts the chain contents in a database for efficient indexing. Most dapps need it. You can read more about indexers [here](https://wiki.tezosagora.org/build/blockchain-indexers).

Current supported indexers:

- [TzKT](https://github.com/baking-bad/tzkt)

Look [here](https://github.com/oxheadalpha/tezos-k8s/blob/master/charts/tezos/values.yaml#L184-L205) in the Tezos Helm chart's values.yaml `indexer` section for how to deploy an indexer.

You must spin up an archive node in your cluster if you want to your indexer to index it. You would do so by configuring a new node's `history_mode` to be `archive`.

You can also spin up a lone indexer without any Tezos nodes in your cluster, but make sure to point the `rpc_url` field to an accessible Tezos archive node's rpc endpoint.

