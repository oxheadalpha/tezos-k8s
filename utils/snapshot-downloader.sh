#!/bin/sh

set -e

data_dir="/var/tezos"
node_dir="$data_dir/node"
node_data_dir="$node_dir/data"
snapshot_file=$node_dir/chain.snapshot

if [ ! -d "$data_dir" ]; then
  echo "ERROR: /var/tezos doesn't exist. There should be a volume mounted."
  exit 1
fi

if [ -d "$node_data_dir/context" ]; then
  echo "Blockchain has already been imported. Exiting."
  exit 0
fi

echo "Did not find a pre-existing blockchain."

if [ "$(cat ${data_dir}/snapshot_config.json)" == "null" ]; then
  echo "No snapshot config found, nothing to do."
  exit 0
fi

echo "Tezos snapshot config is:"
cat ${data_dir}/snapshot_config.json

artifact_url=$(cat ${data_dir}/snapshot_config.json | jq -r '.url')
artifact_type=$(cat ${data_dir}/snapshot_config.json | jq -r '.artifact_type')
mkdir -p "$node_data_dir"

download() {
  # Smart Downloading function. When relevant metadata is accessible, it:
  # * checks that there is enough space to download the file
  # * verifies the sha256sum
  filesize_bytes=$(cat ${data_dir}/snapshot_config.json | jq -r '.filesize_bytes // empty')
  sha256=$(cat ${data_dir}/snapshot_config.json | jq -r '.sha256 // empty')
  if [ ! -z "${filesize_bytes}" ]; then
    free_space=$(findmnt -bno size -T ${data_dir})
    echo "Free space available in filesystem: ${free_space}" >&2
    if [ "${filesize_bytes}" -gt "${free_space}" ]; then
      echo "Error: not enough disk space available to download artifact." >&2
      exit 1
    else
      echo "There is sufficient free space to download the artifact of size ${filesize_bytes}." >&2
    fi
  fi
  curl -LfsS $1 | tee >(sha256sum > ${snapshot_file}.sha256sum)
  if [ ! -z "${sha256}" ]; then
    if [ "${sha256}" != "$(cat ${snapshot_file}.sha256sum | head -c 64)" ]; then
      echo "Error: sha256 checksum of the downloaded file did not match checksum from metadata file." >&2
      exit 1
    else
      echo "Snapshot sha256sum check successful." >&2
    fi
  fi
}

if [ "${artifact_type}" == "tezos-snapshot" ]; then
  echo "Downloading $artifact_url"
  echo '{ "version": "0.0.4" }' > "$node_dir/version.json"
  block_hash=$(cat ${data_dir}/snapshot_config.json | jq -r '.block_hash // empty')
  download "$artifact_url" > "$snapshot_file"
  if [ ! -z "${block_hash}" ]; then
    echo ${block_hash} > ${snapshot_file}.block_hash
  fi
elif [ "${artifact_type}" == "tarball" ]; then
  echo "Downloading and extracting tarball from $artifact_url"
  download "$artifact_url" | lz4 -d | tar -x -C "$data_dir"
fi

chown -R 1000 "$data_dir"
ls -lR "$data_dir"
