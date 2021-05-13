CLIENT="/usr/local/bin/tezos-client -A tezos-node-rpc -P 8732"

until $CLIENT rpc get /version; do
    sleep 2
done

echo Activating chain:
set -x
set -o pipefail
$CLIENT -d /var/tezos/client --block					\
	genesis activate protocol					\
	{{ .Values.activation.protocol_hash }}				\
	with fitness -1 and key						\
	{{ .Values.node_config_network.activation_account_name }}	\
	and parameters /etc/tezos/parameters.json 2>&1 | head -200
