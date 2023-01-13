import datetime
import json
import urllib
import urllib.request
from pathlib import Path
import pprint
from datetime import datetime

import datefinder
import pytz
from genericpath import exists

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

    # Initialize date to now, and then update with build date as we iterate
    last_tezos_build_datetime=datetime.now().replace(tzinfo=pytz.UTC)
    for (type, mode, path) in [("tarball", "rolling", "rolling-tarball"), ("tarball", "archive", "archive-tarball"), ("tezos-snapshot", "rolling", "rolling")]:

        # Parses date from tezos build of each artifact, compares to last date, updates if older, otherwise its newer
        for snapshot in snapshots:
            matches=datefinder.find_dates(snapshot['tezos_version'])
            try:
                tezos_build_datetime=list(matches)[0]
            except IndexError:
                continue
            if tezos_build_datetime < last_tezos_build_datetime:
                latest_tezos_build_version=[src for time, src in datefinder.find_dates(snapshot['tezos_version'], source=True)][1]
                last_tezos_build_datetime=tezos_build_datetime

        # Snapshots of type (tarball/snapshot) and history mode
        typed_snapshots = [s for s in snapshots if s["artifact_type"] == type and s["history_mode"] == mode]
        typed_snapshots.sort(key=lambda x: int(x["block_height"]), reverse=True)

        try:
            # Keep list of all snapshots
            network_snapshots[path] = typed_snapshots
        except IndexError:
            continue

        # Latest should only show oldest supported build so let's filter by the oldest supported version we found above
        typed_snapshots=[t for t in typed_snapshots if latest_tezos_build_version in t['tezos_version']]

        try:
            # Latest snapshot of type is the first item in typed_snapshots which we just filtered by the latest supported tezos build
            network_latest_snapshots[path] = typed_snapshots[0]
        except IndexError:
            continue

    latest_snapshots.append(
        { "name": network, "permalink": network+"/index.html", "latest_snapshots": network_latest_snapshots })
    all_snapshots.append(
        { "name": network, "permalink": network+"/list.html", "snapshots": network_snapshots })

Path("_data").mkdir(parents=True, exist_ok=True)
with open(f"_data/snapshot_jekyll_data.json", 'w') as f:
    json.dump({"latest_snapshots": latest_snapshots, "all_snapshots": all_snapshots}, f, indent=2)
