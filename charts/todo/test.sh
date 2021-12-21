#!/bin/sh
BLOCK_HASH=230948SKLJKLADS
BLOCK_HEIGHT=230948SKLJKLADS
BLOCK_TIMESTAMP=230948SKLJKLADS
ARCHIVE_TARBALL_FILENAME=newfile-$(date +%s).lz4
FILE_URL=ARCHIVE_TARBALL_FILENAME

if ! [ -s "base.json" ]
then
  # It is. Write an empty array to it
  echo '[]' > "base.json"
fi

tmp=$(mktemp)
cp base.json "${tmp}"

jq \
--arg BLOCK_HASH "$BLOCK_HASH" \
--arg BLOCK_HEIGHT "$BLOCK_HEIGHT" \
--arg BLOCK_TIMESTAMP "$BLOCK_TIMESTAMP" \
--arg ARCHIVE_TARBALL_FILENAME "${ARCHIVE_TARBALL_FILENAME}" \
'. |= 
[
  {
    ($ARCHIVE_TARBALL_FILENAME): {
      "contents": {
        "BLOCK_HASH": $BLOCK_HASH,
        "BLOCK_HEIGHT": $BLOCK_HEIGHT,
        "BLOCK_TIMESTAMP": $BLOCK_TIMESTAMP
      }
    }
  }
] 
+ .' "${tmp}" > base.json && rm "${tmp}"


printf "\n\n****JSON FILE****\n\n"
cat base.json