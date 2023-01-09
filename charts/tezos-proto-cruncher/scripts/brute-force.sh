#!/bin/bash
cp -r /mnt/scratch/proto_tmpl /mnt/scratch/proto_${1}
while true; do
  sed -i '$ d' /mnt/scratch/proto_${1}/lib_protocol/main.ml
  echo "(* Vanity nonce: $( od -N 7 -t uL -An /dev/urandom | tr -d " ") *)" >> /mnt/scratch/proto_${1}/lib_protocol/main.ml
  if ./bin/octez-x86_64/octez-protocol-compiler -hash-only /mnt/scratch/proto_${1}/lib_protocol/ | grep -e "^P[rst]${VANITY_STRING}.*" > /dev/null ; then
    proto_hash=$(./bin/octez-x86_64/octez-protocol-compiler -hash-only /mnt/scratch/proto_${1}/lib_protocol/)
    printf "Found ${proto_hash}\n"
    printf "$(cat /mnt/scratch/proto_${1}/lib_protocol/main.ml | grep Vanity)\n" > /home/tezos/${proto_hash}
    s3cmd put /home/tezos/${proto_hash} s3://${BUCKET_NAME}/${PROTO_NAME}_${proto_hash}
  fi
done
