#!/bin/sh

# When the tezos-node boots for the first time, if one of the bootstrap
# nodes can't be contacted, then tezos-node will give up.
# So at first boot (when peers.json is empty) we wait for bootstrap node.
# This is probably a bug in tezos core, though.

if [ -s /var/tezos/node/peers.json ] && [ "$(jq length /var/tezos/node/peers.json)" -gt "0" ]; then
    printf "Node already has an internal list of peers, no need to wait for bootstrap \n"
    exit 0
fi

#
# BOOTSTRAP_NODES will be a space separated list of all of the bootstrap
# nodes.  We use jq to extract this list from $NODES which is passed in.
#
# In the jq, the function expand_nodes() takes a hash description of a
# statefulset in the form:
# {
#	"key" : "statefulset-name",
#        value : { "instances" : [ i0, i1, i2, ... ], etc }
# }
# and converts it into:
# {
#	"statefulsetname-0" : i0,
#	"statefulsetname-0" : i1,
#	"statefulsetname-0" : i2,
#	.
#	.
#	.
# }
#
# expand_all_nodes iterates over the input expanding
# each defined statefulset using expand_nodes(), note
# that a {} + another {} merges them together and so
# the output of expand_all_nodes actually has the same
# schema as that of expand_nodes above.

BOOTSTRAP_NODES=$(echo $NODES | \
    jq -r '
	def expand_nodes(a):
	    reduce (a|(.value.instances // [{}])[] // []) as $f
		([0,{}];
		 [ .[0] + 1,
		   .[1] + { ((a|.key) + "-" + (.[0]|tostring)) : $f}
		 ])
	    |.[1];

	def expand_all_nodes:
	    reduce .[] as $inp ({}; . + expand_nodes($inp));

	 to_entries
	|expand_all_nodes
	|to_entries[]
	|debug
	|select(.value.is_bootstrap_node)
	|.key + "." + (.key|sub("-[\\d]+$"; ""))'
)


if [ -z "$BOOTSTRAP_NODES" ]; then
    echo No bootstrap nodes were provided
    exit 1
fi

HOST=$(hostname -f)
for node in $BOOTSTRAP_NODES; do
    if [ "${HOST##$node}" != "$HOST" ]; then
	echo "I am $node!"
	echo "I'm the one of the bootstrap nodes: do not wait for myself"
	exit 0
    else
	echo "I am not $node!"
    fi
done

#
# wait for node to respond to rpc.  We still sleep between nc(1)'s because
# some errors are instant.
#
# We give the sleep some jitter because that's often helpful when firing
# up a lot of nodes.
#
# We also start off with a bit of a random sleep before we get going under
# the assumption that the bootstrap node will take some time to get going.
# Remember: the bootstrap nodes exit(3)ed above and so this slows down only
# those that are likely to need to wait a minute for it to start.

INTERVAL=1
randomsleep() {
    SLEEP=$(expr $(od -An -N1 -i /dev/random) % 15 + $INTERVAL)
    if [ $SLEEP -gt 30 ]; then
	SLEEP=30
    fi
    echo Sleeping for $SLEEP seconds.
    sleep $SLEEP
    if [ $INTERVAL -lt 20 ]; then
	INTERVAL=$(expr $INTERVAL + 2)
    fi
}

echo "waiting for bootstrap nodes to accept connections"

while :; do
    for node in $BOOTSTRAP_NODES; do
	if </dev/null nc -q 0 ${node} 8732; then
	    echo "$node is up"
	    echo "Found bootstrap node, exiting"
	    exit 0
	fi
	echo "$node is down"
    done
    randomsleep
done
