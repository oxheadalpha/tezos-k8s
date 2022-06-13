#!/bin/sh

extract_markdown() {
  uncommented=false
  IFS=
  echo "$1" | while read -r line; do
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
  done
  if [[ "$uncommented" == "true" ]]; then
     echo '```'
  fi
}

lines=$(cat ../charts/tezos/values.yaml  | awk '/# Nodes/,/End nodes/' | sed '$d' )
extract_markdown "$lines"  > 01-Tezos-Nodes.md
lines=$(cat ../charts/tezos/values.yaml  | awk '/# Accounts/,/End Accounts/' | sed '$d' )
extract_markdown "$lines"  > 02-Tezos-Accounts.md
lines=$(cat ../charts/tezos/values.yaml  | awk '/# Signers/,/End Signers/' | sed '$d' )
extract_markdown "$lines"  > 03-Tezos-Signers.md
