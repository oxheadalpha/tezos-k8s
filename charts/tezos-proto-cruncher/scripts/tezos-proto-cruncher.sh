sudo apk add curl py3-pip parallel bash
sudo pip install s3cmd

mkdir /home/tezos/bin
curl https://gitlab.com/tezos/tezos/-/package_files/61895291/download | tar -xz -C /home/tezos/bin

cat .s3cfg-tpl | \
  sed -e "s/host_base =.*$/host_base = ${HOST_BASE}/" | \
  sed -e "s/host_bucket =.*$/host_bucket = ${HOST_BUCKET}/" > .s3cfg

mkdir protos
cd protos

s3cmd ls s3://${BUCKET_NAME} | awk '{ print $4 }' | grep "${PROTO_NAME}.tar.gz$" | while read line; do
  s3cmd get $line
done
cd ..

# use ramfs for speed
mkdir /mnt/scratch/proto_tmpl
tar -xvf protos/*.tar.gz -C /mnt/scratch/proto_tmpl

cp /home/tezos/brute-force.sh.orig /home/tezos/brute-force.sh
chmod 755 /home/tezos/brute-force.sh

# one process per CPU core
num_cores=$(grep -c ^processor /proc/cpuinfo)
seq $num_cores | parallel --ungroup /home/tezos/brute-force.sh {#}
