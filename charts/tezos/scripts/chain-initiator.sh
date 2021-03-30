CLIENT="/usr/local/bin/tezos-client -A tezos-node-rpc -P 8732"
until $CLIENT rpc get /version; do
    sleep 2
done

echo /etc/tezos/parameters.json contains:
echo ------------------------------------------------------------
cat /etc/tezos/parameters.json
echo ------------------------------------------------------------
echo Activating chain:
set -x
$CLIENT -d /var/tezos/client -l --block
	genesis activate protocol
	{{ .Values.activation.protocol_hash }}
	with fitness -1 and key
	{{ .Values.node_config_network.activation_account_name }}
	and parameters /etc/tezos/parameters.json
