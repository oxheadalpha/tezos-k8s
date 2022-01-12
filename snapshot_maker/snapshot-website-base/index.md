---
# Page settings
layout: snapshot
keywords:
comments: false
# Hero section
title: Tezos snapshots for 
description: 
# Author box
author:
    title: Brought to you by Oxhead Alpha
    title_url: 'https://medium.com/the-aleph'
    external_url: true
    description: A Tezos core development company, providing common goods for the Tezos ecosystem. <a href="https://medium.com/the-aleph" target="_blank">Learn more</a>.
# Micro navigation
micro_nav: true
# Page navigation
page_nav:
    home:
        content: Previous page
        url: 'https://xtz-shots.io/index.html'
---
# Tezos snapshots for 
Block height: 
Block hash: ``
[Verify on TzStats](https://tzstats.com/){:target="_blank"} - [Verify on TzKT](https://tzkt.io/){:target="_blank"}
Block timestamp: 
Tezos version used for snapshotting: ``
## Archive tarball
[Download Archive Tarball](-archive-tarball)
Size: 
## Rolling tarball
[Download Rolling Tarball](-rolling-tarball)
Size: 
## Rolling snapshot
[Download Rolling Snapshot](-rolling-tezos)
Size: 
## How to use
### Archive Tarball
Issue the following commands:
```
curl -LfsS "" | lz4 -d | tar -x -C "/var/tezos"
```
Or simply use the permalink:
```
curl -LfsS "-archive-tarball" | lz4 -d | tar -x -C "/var/tezos"
```
### Rolling Tarball
Issue the following commands:
```
curl -LfsS "" | lz4 -d | tar -x -C "/var/tezos"
```
Or simply use the permalink:
```
curl -LfsS "-rolling-tarball" | lz4 -d | tar -x -C "/var/tezos"
```
### Rolling Snapshot
Issue the following commands:
```
wget 
tezos-node snapshot import  --block 
```
Or simply use the permalink:
```
wget -rolling-tezos -O tezos-.rolling
tezos-node snapshot import tezos-.rolling
```
### More details
[About xtz-shots.io](https://xtz-shots.io/getting-started/).
[Tezos documentation](https://tezos.gitlab.io/user/snapshots.html){:target="_blank"}.
