#!/bin/sh

if [ -d /var/tezos ] ; then
  curl $TARBALL_URL | lz4 -d | tar -x -C /var/tezos
else
  echo "/var/tezos does not exist."
fi