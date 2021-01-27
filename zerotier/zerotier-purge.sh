#!/bin/bash

# Helper script to clean up stale ip's/members in your Zerotier network. The
# list grows as you spin up and down more and more chains during development.
# You eventually get to a point where Zerotier warns you on their site about the
# number of nodes you have on their free plan. Zerotier's site does not provide
# a way to bulk delete members. Please use at your own risk.

# See the 'COMMENT' below for the structure of a member from the
# https://my.zerotier.com/api/network/$ZT_NET/member/$node_id endpoint.

# You can use jq to filter by any field. Your jq filter needs to return a list
# of "nodeId".

# Filter example: Delete all offline nodes
# | jq -r '.[] | select(.online == false) | .nodeId' \

set -euo pipefail

echo "Deleting Zerotier members for network id $ZT_NET..."
curl -sSf -H "Authorization: bearer $ZT_TOKEN" https://my.zerotier.com/api/network/$ZT_NET/member \
| jq -r '.[].nodeId' \
| while read node_id
do
  curl -sSf -X DELETE -H "Authorization: bearer $ZT_TOKEN" https://my.zerotier.com/api/network/$ZT_NET/member/$node_id
  echo "Deleted node id $node_id"
done
echo "Done"


: <<'COMMENT'
{
  "id": "8850338390cc26bf-fd72385a73",
  "type": "Member",
  "clock": 1611618477875,
  "networkId": "8850338390cc26bf",
  "nodeId": "fd72385a73",
  "controllerId": "8850338390",
  "hidden": false,
  "name": "my-chain_bootstrap",
  "online": false,
  "description": "Bootstrap node tezos-baking-node-1 for chain my-chain",
  "config": {
    "activeBridge": false,
    "address": "fd72385a73",
    "authorized": true,
    "capabilities": [],
    "creationTime": 1611611079979,
    "id": "fd72385a73",
    "identity": "fd72385a73:0:75e1b19746959f47113c9a0f4509e7299f7af9579a4d305a0c13c0754b04a92a24336c31d4bbec5a5176186855709a09e3593b90793d472e657eb7de573ad51d",
    "ipAssignments": [
      "172.25.177.31"
    ],
    "lastAuthorizedTime": 1611611094165,
    "lastDeauthorizedTime": 0,
    "noAutoAssignIps": false,
    "nwid": "8850338390cc26bf",
    "objtype": "member",
    "remoteTraceLevel": 0,
    "remoteTraceTarget": null,
    "revision": 9,
    "tags": [],
    "vMajor": 1,
    "vMinor": 4,
    "vRev": 6,
    "vProto": 10
  },
  "lastOnline": 1611611205444,
  "physicalAddress": "24.188.43.79",
  "physicalLocation": null,
  "clientVersion": "1.4.6",
  "protocolVersion": 10,
  "supportsRulesEngine": true
}
COMMENT
