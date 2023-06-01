CLIENT="/usr/local/bin/octez-client --endpoint http://tezos-node-rpc:8732"
echo "LALAL"

until $CLIENT rpc get /chains/main/blocks/head/header | grep '"level":'; do
    sleep 2
done

set -o pipefail
if ! $CLIENT rpc get /chains/main/blocks/head/header | grep '"level": 0,'; then
    echo "Chain already activated, considering activation successful and exiting"
    exit 0
fi

# Substitute #fromfile with the hex encoded files in question.
# This is for bootstrapped smart rollups.



PARAMETERS_FILE='/etc/tezos/parameters.json'
TMP_PARAMETERS_FILE='/etc/tezos/tmp_parameters.json'

# Pattern to search for
pattern='fromfile#'

# Buffer for characters
buffer=''

# Whether 'fromfile#' was detected
detected_fromfile=false

# Process each character
while IFS= read -r -n1 char
do
  # Add the character to the buffer
  buffer=$(printf "%s%s" "$buffer" "$char")

  # If the buffer ends with the pattern
  if [ "${buffer%"$pattern"}" != "$buffer" ]
  then
    detected_fromfile=true

    # Clear the buffer
    buffer=''

    # Read the filename
    filename=''
    while IFS= read -r -n1 char && [ "$char" != '"' ]
    do
      filename=$(printf "%s%s" "$filename" "$char")
    done

    echo "Found kernel file: $filename"

    # Check if file exists
    if [ ! -f "$filename" ]; then
      echo "Kernel file $filename not found!"
      exit 1
    fi

    # Convert the file content to hex and append to the temp file
    xxd -ps -c 256 "$filename" | tr -d '\n' >> $TMP_PARAMETERS_FILE

    # Add a closing double quote
    printf '"' >> $TMP_PARAMETERS_FILE
  elif [ ${#buffer} -ge ${#pattern} ]
  then
    # Write the oldest character in the buffer to the temporary file
    printf "%s" "${buffer%"${buffer#?}"}" >> $TMP_PARAMETERS_FILE

    # Remove the oldest character from the buffer
    buffer=${buffer#?}
  fi
done < "$PARAMETERS_FILE"

# If there's anything left in the buffer, write it to the file
if [ -n "$buffer" ]
then
  printf "%s" "$buffer" >> $TMP_PARAMETERS_FILE
fi

# Replace the original parameters.json file with the modified one only if 'fromfile#' was detected
if $detected_fromfile; then
  mv $TMP_PARAMETERS_FILE $PARAMETERS_FILE
  echo "Updated JSON saved in '$PARAMETERS_FILE'"
else
  rm -f $TMP_PARAMETERS_FILE
  echo "No 'fromfile#' detected in '$PARAMETERS_FILE', no changes made."
fi
echo Activating chain:
$CLIENT -d /var/tezos/client --block					\
	genesis activate protocol					\
	{{ .Values.activation.protocol_hash }}				\
	with fitness 1 and key						\
	$( cat /etc/tezos/activation_account_name )			\
	and parameters $PARAMETERS_FILE 2>&1 | head -200
sleep 10000
