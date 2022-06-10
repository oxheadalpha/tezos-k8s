
extract_markdown() {
  uncommented=false
  while IFS= read -r line; do
    if [[ $line =~ ^# ]]; then
      if [[ "$uncommented" == "true" ]]; then
         echo '```'
      fi
      uncommented=false
      echo "$line" | sed -e 's/^# //'  | sed -e 's/^#$//'
    else
      if [[ "$uncommented" == "false" ]]; then
         echo '```'
      fi
      uncommented=true
      echo "$line"
    fi
  done <<< $1
  if [[ "$uncommented" == "true" ]]; then
     echo '```'
  fi
}

lines=$(cat charts/tezos/values.yaml  | awk '/# Nodes/,/End nodes/' | head -n -1)
extract_markdown "$lines"  > docs/01-Tezos-Nodes.md
lines=$(cat charts/tezos/values.yaml  | awk '/# Accounts/,/End Accounts/' | head -n -1)
extract_markdown "$lines"  > docs/02-Tezos-Accounts.md
