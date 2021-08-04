#!/bin/sh -x

CMD="$1"
shift

case "$CMD" in
	config-generator)	exec /config-generator.sh	"$@"	;;
	logger)			exec /logger.sh			"$@"	;;
	snapshot-downloader)	exec /snapshot-downloader.sh	"$@"	;;
	wait-for-bootstrap)	exec /wait-for-bootstrap.sh	"$@"	;;
esac

#
# As we exec above, reaching here means that we did not
# find the command we were provided.

echo "ERROR: could not find \"$CMD\"."
echo
echo "Valid options are:"
echo "	config-generator"
echo "	logger"
echo "	snapshot-downloader"
echo "	wait-for-bootstrap"
