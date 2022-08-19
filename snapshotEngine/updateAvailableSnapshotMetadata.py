from genericpath import exists
import os
import urllib, json
import urllib.request
import boto3
import sys

allSubDomains = os.environ['ALL_SUBDOMAINS'].split(",")

filename="snapshots.json"

# Write empty top-level array to initialize json
json_object = []

# Get each subdomain's base.json and combine all artifacts into 1 metadata file
for subDomain in allSubDomains:
  with urllib.request.urlopen("https://"+subDomain+".xtz-shots.io/base.json") as url:
    data = json.loads(url.read().decode())
    for entry in data:
      json_object.append(entry)

# Write to file
with open (filename, 'w') as json_file:
  json_string = json.dumps(json_object, indent=4)
  json_file.write(json_string)

# build page data
with urllib.request.urlopen("https://new.xtz-shots.io/snapshots.json") as url:
    snapshots = json.loads(url.read().decode())
from pathlib import Path


# sort per network
snapshots_per_network = {}

# for some reason, the first page is empty, so we initialize the map with dummy data to generate a first page
# The error is:
#   Error reading file /home/nochem/workspace/xtz-shots-website/_layouts/latest_snapshots.md/latest_snapshots.md: Not a directory @ rb_sysopen - /home/nochem/workspace/xtz-shots-website/_layouts/latest_snapshots.md/latest_snapshots.md
latest_snapshots = [{ "name": "example", "latest_snapshots" : {}}]

for snapshot in snapshots:
    network = snapshot["chain_name"]
    if network not in snapshots_per_network:
        snapshots_per_network[network] = []
    snapshots_per_network[network].append(snapshot)

for network, snapshots in snapshots_per_network.items():
    network_latest_snapshots = {}
    for (type, mode, path) in [("tarball", "rolling", "rolling-tarball"), ("tarball", "archive", "archive-tarball"), ("tezos-snapshot", "rolling", "rolling")]:
        typed_snapshots = [s for s in snapshots if s["artifact_type"] == type and s["history_mode"] == mode]
        typed_snapshots.sort(key=lambda x: int(x["block_height"]), reverse=True)
        network_latest_snapshots[path] = typed_snapshots[0]
    latest_snapshots.append(
        { "name": network, "permalink": network, "latest_snapshots": network_latest_snapshots })

Path("_data").mkdir(parents=True, exist_ok=True)
with open(f"_data/snapshot_jekyll_data.json", 'w') as f:
    json.dump({"latest_snapshots": latest_snapshots}, f, indent=2)