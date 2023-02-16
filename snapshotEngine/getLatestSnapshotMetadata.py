import json
from pathlib import Path
import random
from genericpath import exists

import pprint
pp = pprint.PrettyPrinter(indent=4)

filename='tezos-snapshots.json'

if exists(filename):
    print('SUCCESS tezos-snapshots.json exists locally!')
    with open(filename,'r') as localJson:
        snapshots = json.load(localJson)
else:
    print('ERROR tezos-snapshots.json does not exist locally!')

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

    # Find a lowest version available for a given network, artifact_type, and history_mode
    for (artifact_type, history_mode, path) in [("tarball", "rolling", "rolling-tarball"), ("tarball", "archive", "archive-tarball"), ("tezos-snapshot", "rolling", "rolling")]:
        # List of snapshot metadata for this particular artifact type and history mode
        typed_snapshots = [s for s in snapshots if s["artifact_type"] == artifact_type and s["history_mode"] == history_mode]
        
        # Lowest version is the top item (int) of a sorted unique list of all the versions for this particular artifact type and history mode
        octez_versions = sorted(list(set([ s['tezos_version']['version']['major'] for s in typed_snapshots if 'version' in s['tezos_version'] ])))
        if octez_versions:
            lowest_octez_version = octez_versions[0]
        else:
            # no metadata yet for this namespace, ignoring
            continue

        network_snapshots[path] = typed_snapshots

        # Latest offered should only show oldest supported build so let's filter by the oldest supported version we found above
        typed_snapshots = [d for d in typed_snapshots if 'version' in d['tezos_version'] and d['tezos_version']['version']['major'] == lowest_octez_version ]

            # Latest snapshot of type is the last item in typed_snapshots which we just filtered by the latest supported tezos build
        network_latest_snapshots[path] = typed_snapshots[-1]

    # This becomes the list of snapshots
    latest_snapshots.append(
        { "name": network, "permalink": network+"/index.html", "latest_snapshots": network_latest_snapshots })
    all_snapshots.append(
        { "name": network, "permalink": network+"/list.html", "snapshots": network_snapshots })

Path("_data").mkdir(parents=True, exist_ok=True)
filename = "_data/snapshot_jekyll_data.json"
with open(filename, 'w') as f:
    json.dump({"latest_snapshots": latest_snapshots, "all_snapshots": all_snapshots}, f, indent=2)
print(f"Done writing structured list of snapshots for Jekyll to render webpage: {filename}")
