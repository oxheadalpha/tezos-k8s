#!/usr/bin/env bash
set -e

source ${BASH_SOURCE%/*}/env

usage() {
    echo "OPTIONS:"
    echo "  [--chain-name]  private chain name [--work-dir]  storage directory"
}

tezos_client() {
    docker run --entrypoint /usr/local/bin/tezos-client -u $UID --rm -v $WORK_DIR/client:/data $DOCKER_IMAGE -d /data --protocol PsCARTHAGazK "$@"
}

gen_key() {
    # generate a genesis key
    tezos_client gen keys $1 --force
}

get_key() {
    tezos_client show address $1 | awk -F: ' /Public Key/ { printf $2 }'
}

write_config() {
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    GENESIS_PUBKEY=$(get_key genesis)

# make node.json with the newly created genesis key
    cat > "$WORK_DIR/node/config.json" << EOM
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
      "listen-addr": "[::]:8732",
      "expected-proof-of-work": 0
    },
    "network": {
        "genesis": {
            "timestamp": "$TIMESTAMP",
            "block": "BLockGenesisGenesisGenesisGenesisGenesisd6f5afWyME7",
            "protocol": "PtYuensgYBb3G3x1hLLbCmcav8ue8Kyd2khADcL5LsT5R1hcXex"
        },
        "genesis_parameters": {
            "values": {
            "genesis_pubkey": "$GENESIS_PUBKEY"
            }
        },
        "chain_name": "$CHAIN_NAME",
        "sandboxed_chain_name": "SANDBOXED_TEZOS",
        "default_bootstrap_peers": []
    }
}
EOM
}

write_parameters() {
    BOOTSTRAP_ACCOUNT_1=$(get_key bootstrap_account_1)
    BOOTSTRAP_ACCOUNT_2=$(get_key bootstrap_account_2)
    BOOTSTRAP_ACCOUNT_3=$(get_key bootstrap_account_3)

    cat > "$WORK_DIR/client/parameters.json"<< EOM
{
    "bootstrap_accounts": [
      [
        "$BOOTSTRAP_ACCOUNT_1",
        "4000000000000"
      ],
      [
        "$BOOTSTRAP_ACCOUNT_2",
        "4000000000000"
      ],
      [
        "$BOOTSTRAP_ACCOUNT_3",
        "4000000000000"
      ]
    ],
    "preserved_cycles": 2,
    "blocks_per_cycle": 8,
    "blocks_per_commitment": 4,
    "blocks_per_roll_snapshot": 4,
    "blocks_per_voting_period": 64,
    "time_between_blocks": [
      "10",
      "20"
    ],
    "endorsers_per_block": 32,
    "hard_gas_limit_per_operation": "800000",
    "hard_gas_limit_per_block": "8000000",
    "proof_of_work_threshold": "0",
    "tokens_per_roll": "8000000000",
    "michelson_maximum_type_size": 1000,
    "seed_nonce_revelation_tip": "125000",
    "origination_size": 257,
    "block_security_deposit": "512000000",
    "endorsement_security_deposit": "64000000",
    "endorsement_reward": [ "2000000" ],
    "cost_per_byte": "1000",
    "hard_storage_limit_per_operation": "60000",
    "test_chain_duration": "1966080",
    "quorum_min": 2000,
    "quorum_max": 7000,
    "min_proposal_quorum": 500,
    "initial_endorsers": 1,
    "delay_per_missing_endorsement": "1",
    "baking_reward_per_endorsement": [ "200000" ]
}
EOM
}

gen_id() {
    # generate first node id using genesis config
    docker run -u $UID --rm --entrypoint "/usr/local/bin/tezos-node" -v $WORK_DIR/node:/data $DOCKER_IMAGE identity generate 0 --data-dir /data --config-file /data/config.json
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
        --work-dir)
            WORK_DIR="$2"
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

mkdir -p $WORK_DIR/{node,client}
gen_key genesis
gen_key bootstrap_account_1
gen_key bootstrap_account_2
gen_key bootstrap_account_3
write_config
write_parameters
gen_id
