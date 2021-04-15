set -ex

set

/usr/local/bin/tezos-node run				\
		--bootstrap-threshold 0			\
		--config-file /etc/tezos/config.json
