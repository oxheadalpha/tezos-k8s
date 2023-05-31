CLIENT="/usr/local/bin/octez-client --endpoint http://tezos-node-rpc:8732"

until $CLIENT rpc get /chains/main/blocks/head/header | grep '"level":'; do
    sleep 2
done

set -x
set -o pipefail
if ! $CLIENT rpc get /chains/main/blocks/head/header | grep '"level": 0,'; then
    echo "Chain already activated, considering activation successful and exiting"
    exit 0
fi

PARAMS_FILE='/etc/tezos/parameters.json'

# Check if there are any bootstrap rollups. If present, replace the file with its content.
size=$(jq '.bootstrap_parameters.bootstrap_smart_rollups | length' $PARAMS_FILE)

# Iterate over each object in the bootstrap_smart_rollups array
for (( i=0; i<$size; i++ ))
do
    KERNEL_FILE=$(jq -r ".bootstrap_parameters.bootstrap_smart_rollups[$i].kernel_from_file" $PARAMS_FILE)

    # Check if file exists
    if [ ! -f "$KERNEL_FILE" ]; then
      echo "Kernel file $KERNEL_FILE not found!"
      exit 1
    fi

    # Convert the file content to hex
    HEX_KERNEL=$(xxd -ps -c 256 $KERNEL_FILE | tr -d '\n')

    # Replace kernel_from_file with kernel in JSON, and write to a temporary file
    jq --arg kernel "$HEX_KERNEL" ".bootstrap_parameters.bootstrap_smart_rollups[$i] |= del(.kernel_from_file) | .bootstrap_parameters.bootstrap_smart_rollups[$i] += {\"kernel\": \$kernel}" $PARAMS_FILE > temp.json

    # Move the temporary file back to the original file
    mv temp.json $PARAMS_FILE
done

echo Activating chain:
$CLIENT -d /var/tezos/client --block					\
	genesis activate protocol					\
	{{ .Values.activation.protocol_hash }}				\
	with fitness 1 and key						\
	$( cat /etc/tezos/activation_account_name )			\
	and parameters /etc/tezos/parameters.json 2>&1 | head -200
