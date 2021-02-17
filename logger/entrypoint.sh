#!/bin/sh

DELAY=15
HOST="$(hostname)"
TOP=http://127.0.0.1:8732/chains/main/blocks/

TMPFILE=$(mktemp)
bail() {
    rm "$TMPFILE"
}
trap bail 0

warning() {
    # XXXrcd: maybe this should be JSON, too?
    echo "$@" 1>&2
}

find_last_block() {
    PREV_RUN="$1"

    i=0
    LAST=head
    BLOCKS=
    while :; do
	HASH="$(curl -s "$TOP/$LAST/header" | jq -r .predecessor)"
	if [ "$LAST" = head -a "$HASH" = "$PREV_RUN" ]; then
	    # we must wait for at least one block to be added
	    sleep $DELAY
	fi
	BLOCKS="$HASH $BLOCKS"
        LAST="$HASH"
        if [ "$HASH" = "$PREV_RUN" ]; then
	    break
	fi
	i=$(expr $i + 1)
        if expr $i \> 20 >/dev/null; then
	    break
        fi
    done

    if [ ! -z "$PREV_RUN" -a "$HASH" != "$PREV_RUN" ]; then
	echo "$BLOCKS" | sed 's/^.* \([^ ]* [^ ]*\)/\1/'
    else
	echo "$BLOCKS"
    fi
}

LAST=
LAST_LEVEL=0
while :; do

    REORG=false
    PREV=
    for BLOCK in $(find_last_block $LAST); do
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
		    "reorg"                 : .[0].reorg,
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

#
# XXXrcd: old code:

#    ( echo '{ "last_hash" : "'$LAST_HASH'", "node" : "'$HOST'" }'; \
#      cat "$TMPFILE" ) |					   \
#	jq --slurp -c '
#	    ( .[0].last_level > 0 and
#	      .[1].header.level > .[0].last_level + 1 )
#		as $missed
#	    | ( $missed == false and
#	        .[1].header.predecessor == .[0].last_hash )
#		as $reorg
#	    | (.[1].operations[0]|length) as $num_ops
#            | (.[2]|length) as $poss_ops
#	    |{
#		"logtype"               : "new-block-on-node",
#		"node"                  : .[0].node,
#		"level"                 : .[1].header.level,
#		"priority"              : .[1].header.priority,
#		"hash"                  : .[1].hash,
#		"last_hash"             : .[0].last_hash,
#		"predecessor"           : .[1].header.predecessor,
#		"missed"                : $missed,
#		"reorg"                 : $reorg,
#		"num_endorsements"      : $num_ops,
#		"possible_endorsements" : $poss_ops,
#		"percent_endorsed"      : ($num_ops / $poss_ops * 100),
#	    }'
#
#    LAST_HASH="$( < "$TMPFILE" jq --slurp -r '.[0].header.hash')"
#    LAST_LEVEL="$(< "$TMPFILE" jq --slurp -r '.[0].header.level')"
#
#    sleep $DELAY
#done
#
# NOTREACHED!
#exit 1
