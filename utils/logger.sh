#!/bin/sh

#
# This script polls the local Tezos node and will emit a single line
# of JSON each time a block is baked.  Each line will be of the form:
#	{
#		"logtype": "new-block-on-node",
#		"node": "private-node-0",
#		"level": 7896,
#		"priority": 0,
#		"hash": "BMYz...",
#		"last_hash": null,
#		"predecessor": "BLeH...",
#		"timestamp": "2021-06-21T20:35:39Z",
#		"reorg": false,
#		"operations": {
#		"endorsement_with_slot": 3
#		},
#		"num_endorsements": 3,
#		"possible_endorsements": 5,
#		"percent_endorsed": 60
#	}

DELAY=15
HOST="$(hostname)"
TOP=http://127.0.0.1:8732/chains/main/blocks

TMPFILE=$(mktemp)
bail() {
    rm "$TMPFILE"
}
trap bail 0

warning() {
    # XXXrcd: maybe this should be JSON, too?
    echo "$@" 1>&2
}

#
# find_next_blocks() takes a block hash as input and finds all of the
# blocks that come after it.  We poll until at least one block has been
# generated.  We limit the search to 20 blocks and in that case only
# return the two latest blocks---this is only expected if we have a
# reorganisation.

find_next_blocks() {
    STOP_AT_BLOCK="$1"

    i=0
    CUR_BLOCK=head
    BLOCKS=
    while :; do
	HASH="$(curl -s "$TOP/$CUR_BLOCK/header" | jq -r .predecessor)"
	if [ "$CUR_BLOCK" = head -a "$HASH" = "$STOP_AT_BLOCK" ]; then
	    # we must wait for at least one block to be added
	    sleep $DELAY
	fi
	BLOCKS="$HASH $BLOCKS"
        CUR_BLOCK="$HASH"
        if [ "$HASH" = "$STOP_AT_BLOCK" ]; then
	    break
	fi
	i=$(expr $i + 1)
        if expr $i \> 20 >/dev/null; then
	    break
        fi
    done

    if [ ! -z "$STOP_AT_BLOCK" -a "$HASH" != "$STOP_AT_BLOCK" ]; then
	echo "$BLOCKS" | sed -E 's/.* ([^ ]* )/\1/'
    else
	echo "$BLOCKS"
    fi
}

LAST=
while :; do

    REORG=false
    PREV=
    for BLOCK in $(find_next_blocks $LAST); do
	if [ -z "$PREV" ]; then
	    if [ "$BLOCK" != "$LAST" ]; then
		REORG=true
	    fi
	    PREV="$BLOCK"
	    continue
	fi

	( echo '{ "reorg" : '$REORG', "node" : "'$HOST'" }';		  \
	  curl -s $TOP/$BLOCK $TOP/$PREV/helpers/endorsing_rights )	| \
	    jq --slurp -c '
		  (.[1].operations[0]|length) as $num_ops
		| (.[2]|length) as $poss_ops
		|{
		    "logtype"               : "new-block-on-node",
		    "node"                  : .[0].node,
		    "level"                 : .[1].header.level,
		    "priority"              : .[1].header.priority,
		    "hash"                  : .[1].hash,
		    "last_hash"             : .[0].last_hash,
		    "predecessor"           : .[1].header.predecessor,
		    "timestamp"             : .[1].header.timestamp,
		    "reorg"                 : .[0].reorg,
		    "operations"            : ([.[1].operations[][]
		    				.contents[]
		    				.kind
					       ]|reduce .[] as $item
						      ({}; .[$item] += 1)
			                      ),
		    "num_endorsements"      : $num_ops,
		    "possible_endorsements" : $poss_ops,
		    "percent_endorsed"      : (if $poss_ops != 0 then
					          ($num_ops / $poss_ops * 100)
					      else -1 end)
		}'

	PREV=$BLOCK
	LAST=$BLOCK
    done
done

# NOTREACHED!
exit 1
