# Tezos RPC Authentication

`rpc-auth` provides a mechanism where a user authenticates themselves and will receive a secret url that they then use to make RPC calls.

## Deploy RPC Auth Backend

This assumes that you have followed the steps [here](../README.md) necessary to deploy a Tezos private chain.

To deploy an RPC Authentication backend for your private chain, do either:

- Run your original `mkchain` command with the flags you used (i.e. Zerotier flags), adding in the `--rpc-auth` flag:

  ```shell
  mkchain $CHAIN_NAME ... --rpc-auth
  ```

- Or manually add the field `rpc_auth: true` in your generated Helm values file `<CURRENT WORKING DIRECTORY>/${CHAIN_NAME}_values.yaml`.

If you don't currently have a chain running, run the following command to start it:
```shell
helm install $CHAIN_NAME charts/tezos \
--values <CURRENT WORKING DIRECTORY>/${CHAIN_NAME}_values.yaml \
--namespace tqtezos --create-namespace
```

If you already have a chain running, you need to use Helm's `upgrade` cmd instead of `install`:
  ```shell
  helm upgrade $CHAIN_NAME charts/tezos \
  --values <CURRENT WORKING DIRECTORY>/${CHAIN_NAME}_values.yaml \
  --namespace tqtezos
  ```

## Client Authentication

### Prerequisites

- [tezos-client](https://assets.tqtezos.com/docs/setup/1-tezos-client/)

## Authentication flow

1. You provide a trusted user with your cluster ip/address and your private tezos chain id.
   To see your chain id, either:

   - ```shell
     kubectl exec -it -n tqtezos deployment/tezos-bootstrap-node -c tezos-node -- tezos-client rpc get /chains/main/chain_id
     ```
   - Use Lens to view the logs of the Tezos node
   - Manually run the logs command `kubectl logs -n tqtezos deployment/tezos-bootstrap-node -c tezos-node`. The top of the logs should look similar to:
     ```
     Dec 21 19:42:08 - node.main: starting the Tezos node (chain = my-chain)
     Dec 21 19:42:08 - node.main: disabled local peer discovery
     Dec 21 19:42:08 - node.main: read identity file (peer_id = idsbTksk6cHggEndHLQBAJvxaViUnz)
     Dec 21 19:42:08 - main: shell-node initialization: bootstrapping
     Dec 21 19:42:08 - main: shell-node initialization: p2p_maintain_started
     Dec 21 19:42:08 - block_validator_process_external: Initialized
     Dec 21 19:42:08 - block_validator_process_external: Block validator started on pid 11
     Dec 21 19:42:08 - validator.block: Worker started
     Dec 21 19:42:08 - node.validator: activate chain NetXitypWekag8Z
     ```
     The chain id is printed on the last line: `NetXitypWekag8Z`.

2. The user needs to have a Tezos secret key either generated or imported by `tezos-client`. The user's secret key is used to sign some data for the server to then verify.

3. The user runs: `rpc-auth/client/init.sh --cluster-address $CLUSTER_IP --tz-alias $TZ_ALIAS --chain-id $CHAIN_ID`

   - `TZ_ALIAS` is the alias of a user's tz address secret key.

4. If the user is authenticated, the response should contain a secret url that looks like `http://192.168.64.51/tezos-node-rpc/ffff3eb3d7dd4f6bbff3f2fd096722ae/`

5. Client can then make RPC requests:
   - `curl http://192.168.64.51/tezos-node-rpc/ffff3eb3d7dd4f6bbff3f2fd096722ae/chains/main/chain_id`
   - Bug in tezos client v8, so as of version `tezos/tezos:master_08d3405e_20201113152010`:
     - `tezos-client --endpoint http://192.168.64.51/tezos-node-rpc/ffff3eb3d7dd4f6bbff3f2fd096722ae/ rpc get chains/main/chain_id`
