CLIENT="/usr/local/bin/octez-client --endpoint http://tezos-node-rpc:8732"

OUTPUT=""
until OUTPUT=$($CLIENT rpc get /chains/main/blocks/head/header) && echo "$OUTPUT" | grep '"level":'; do
    sleep 2
done

set -x
set -o pipefail
if ! echo "$OUTPUT" | grep '"level": 0,'; then
    echo "Chain already activated, considering activation successful and exiting"
    exit 0
fi

echo Activating chain:
$CLIENT -d /var/tezos/client --block                                    \
        genesis activate protocol                                       \
        {{ .Values.activation.protocol_hash }}                          \
        with fitness 1 and key                                          \
        $( cat /etc/tezos/activation_account_name )                     \
        and parameters /etc/tezos/parameters.json 2>&1 | head -200
