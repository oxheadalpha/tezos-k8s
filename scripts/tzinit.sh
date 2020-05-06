#!/usr/bin/env bash
set -e

source ${BASH_SOURCE%/*}/env
WORK_DIR=$PROJECT_ROOT_DIR/work
mkdir -p $WORK_DIR/{node,client}

usage() {
    echo "OPTIONS:"
    echo "  [--chain-name]  private chain name"
}


gen_key() {
    # generate a genesis key
    docker run --entrypoint /usr/local/bin/tezos-client -u $UID --rm -v $WORK_DIR/client:/data $DOCKER_IMAGE -d /data --protocol PsCARTHAGazK gen keys genesis --force
}

write_config() {

    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    GENESIS_PUBKEY=$(cat $WORK_DIR/client/public_keys |jq '.[0] | select(.name=="genesis").value | .[12:]')

# make node.json with the newly created genesis key
    cat > "$WORK_DIR/node/config.json" <<- EOM
{
    "data-dir": "/var/tezos/node",
    "rpc": {
      "listen-addrs": [
        ":8733"
      ]
    },
    "p2p": {
      "bootstrap-peers": [
      ],
      "listen-addr": "[::]:8732"
    },
    "network": {
        "genesis": {
            "timestamp": "$TIMESTAMP",
            "block": "BLockGenesisGenesisGenesisGenesisGenesisd6f5afWyME7",
            "protocol": "PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex"
        },
        "genesis_parameters": {
            "values": {
            "genesis_pubkey": $GENESIS_PUBKEY
            }
        },
        "chain_name": "$CHAIN_NAME",
        "sandboxed_chain_name": "SANDBOXED_TEZOS",
        "default_bootstrap_peers": []
    }
}
EOM
}

gen_id() {
    # generate first node id using genesis config
    docker run -u $UID --rm --entrypoint "/usr/local/bin/tezos-node" -v $WORK_DIR/node:/data $DOCKER_IMAGE identity generate --data-dir /data --config-file /data/config.json
}

while true; do
    if [[ $# -eq 0 ]]; then
        break
    fi
    case "$1" in
        --chain-name)
            CHAIN_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unexpected option \"$1\"."
            usage
            exit 1
            ;;
    esac
done

exit_flag="false"

if [[ -z ${CHAIN_NAME:-} ]]; then
    echo "\"--chain-name\" wasn't provided."
    exit_flag="true"
fi

[[ $exit_flag == "true" ]] && exit 1

gen_key
write_config
gen_id
