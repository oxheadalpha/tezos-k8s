#!/bin/sh -x

CMD="$1"
shift

case "$CMD" in
  snapshot-scheduler) exec /snapshot-scheduler.sh "$@" ;;
  snapshot-maker)     exec /snapshot-maker.sh "$@" ;;
  zip-and-upload)     exec /zip-and-upload.sh "$@" ;;
esac

#
# As we exec above, reaching here means that we did not
# find the command we were provided.

echo "ERROR: could not find \"$CMD\"."
echo
echo "Valid options are:"
echo "	snapshot-scheduler"
echo "	snapshot-maker"
echo "	zip-and-upload"

exit 1
