from genericpath import exists
import urllib, json
import urllib.request
from pathlib import Path

filename='snapshots.json'

if exists(filename):
    print('SUCCESS snapshots.json exists locally!')
    with open(filename,'r') as localJson:
        snapshots = json.load(localJson)
else:
    print('ERROR snapshots.json does not exist locally!')

# sort per network
snapshots_per_network = {}

# for some reason, the first page is empty, so we initialize the map with dummy data to generate a first page
# The error is:
#   Error reading file /home/nochem/workspace/xtz-shots-website/_layouts/latest_snapshots.md/latest_snapshots.md: Not a directory @ rb_sysopen - /home/nochem/workspace/xtz-shots-website/_layouts/latest_snapshots.md/latest_snapshots.md
latest_snapshots = [{ "name": "example", "latest_snapshots" : {}}]

all_snapshots = [{ "name": "example", "all_snapshots" : {}}]

for snapshot in snapshots:
    network = snapshot["chain_name"]
    if network not in snapshots_per_network:
        snapshots_per_network[network] = []
    snapshots_per_network[network].append(snapshot)

for network, snapshots in snapshots_per_network.items():
    network_latest_snapshots = {}
    network_snapshots = {}
    for (type, mode, path) in [("tarball", "rolling", "rolling-tarball"), ("tarball", "archive", "archive-tarball"), ("tezos-snapshot", "rolling", "rolling")]:
        typed_snapshots = [s for s in snapshots if s["artifact_type"] == type and s["history_mode"] == mode]
        typed_snapshots.sort(key=lambda x: int(x["block_height"]), reverse=True)
        try:
            network_latest_snapshots[path] = typed_snapshots[0]
            network_snapshots[path] = typed_snapshots
        except IndexError:
            continue
    latest_snapshots.append(
        { "name": network, "permalink": network+"/index.html", "latest_snapshots": network_latest_snapshots })
    all_snapshots.append(
        { "name": network, "permalink": network+"/list.html", "snapshots": network_snapshots })

Path("_data").mkdir(parents=True, exist_ok=True)
with open(f"_data/snapshot_jekyll_data.json", 'w') as f:
    json.dump({"latest_snapshots": latest_snapshots, "all_snapshots": all_snapshots}, f, indent=2)
