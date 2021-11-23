CLIENT="/usr/local/bin/tezos-client --endpoint http://tezos-node-rpc:8732"

until $CLIENT rpc get /chains/main/blocks/head/header | grep '"level":'; do
    sleep 2
done

set -x
set -o pipefail

activation_fitness_param="{{ .Values.activation.fitness }}"
if [  -z "$activation_fitness_param" ]; then
    FITNESS=$activation_fitness_param
else
    FITNESS="-1"
fi


echo Activating chain:
$CLIENT -d /var/tezos/client --block					\
	genesis activate protocol					\
	{{ .Values.activation.protocol_hash }}				\
	with fitness ${FITNESS} and key					\
	$( cat /etc/tezos/activation_account_name )			\
	and parameters /etc/tezos/parameters.json 2>&1 | head -200
