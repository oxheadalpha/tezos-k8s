set -x

set

TEZOS_NODE=/usr/local/bin/tezos-node

ARGS="--bootstrap-threshold 0 --config-file /etc/tezos/config.json"

#
# If we have a public/private node, then we supply additional arguments
# to set each of them up.  The private node will listen on localhost,
# whereas the public node listens on the exposed interfaces.

if [ "$HAS_PRIVATE_NODE" = 1 ]; then
	if [ "$DAEMON" = private-node ]; then
		ARGS="$ARGS --private-mode"
		ARGS="$ARGS -d /var/tezos/private-node"
		ARGS="$ARGS --net-addr 127.0.0.1:9999"
		ARGS="$ARGS --rpc-addr 127.0.0.1"
		ARGS="$ARGS --no-bootstrap-peers --peer $MY_POD_IP"
	else
		ARGS="$ARGS --rpc-addr $MY_POD_IP"
		ARGS="$ARGS --connections 10"
	fi
fi

#
# Not every error is fatal on start.  In particular, with zerotier,
# the listen-addr may not yet be bound causing tezos-node to fail.
# So, we try a few times with increasing delays:

for d in 1 1 5 10 20 60 120; do
	$TEZOS_NODE run	$ARGS
	sleep $d
done

#
# Keep the container alive for troubleshooting on failures:

sleep 3600
