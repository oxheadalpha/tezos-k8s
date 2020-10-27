#!/bin/bash

# set -e
set -eo pipefail

while test $# -gt 0; do
  case "$1" in
  -h | --help)
    echo "options:"
    echo "-h, --help                show brief help"
    echo "--cluster-address         specify ip or url for requesting nonce"
    echo "--chain-id                specify chain id of permission chain"
    echo "--tz-alias                specify tz alias of your key"
    exit 0
    ;;
  --cluster-address)
    shift
    if test $# -gt 0; then
      export CLUSTER_ADDRESS=$1
    else
      echo "no address specified"
      exit 1
    fi
    shift
    ;;
  --chain-id)
    shift
    if test $# -gt 0; then
      export CHAIN_ID=$1
    else
      echo "no chain id specified"
      exit 1
    fi
    shift
    ;;
  --tz-alias)
    shift
    if test $# -gt 0; then
      export TZ_ALIAS=$1
    else
      echo "no tz alias specified"
      exit 1
    fi
    shift
    ;;
  *)
    break
    ;;
  esac
done


if [ -z "$CLUSTER_ADDRESS" ]
then
  echo "--cluster-address flag is required"
  exit 1
elif [ -z "$CHAIN_ID" ]
then
  echo "--chain-id flag is required"
  exit 1
elif [ -z "$TZ_ALIAS" ]
then
  echo "--tz-alias flag is required"
  exit 1
fi

if ! tezos-client show address $TZ_ALIAS >/dev/null 2>&1
then
 echo "no public key hash alias named $TZ_ALIAS"
 exit 1
fi

nonce_request=$(curl -s -X GET http://localhost:8080/vending-machine/$CHAIN_ID -w " HTTPSTATUS:%{http_code}")
# nonce_request=$(curl -s -X GET http://$CLUSTER_ADDRESS/vending-machine/$CHAIN_ID -w " HTTPSTATUS:%{http_code}")
body=$(echo $nonce_request | sed -e 's/ HTTPSTATUS\:.*//g')
status=$(echo $nonce_request | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

echo nonce_request $nonce_request
echo status $status
echo body $body ${#body}
if [ "$status" -ne "200" ]
then
  echo "Error [HTTP status: $status]"
  exit 1
fi

SIGNATURE=$(tezos-client -p PsCARTHAGazK sign bytes 0x05${body} for ${TZ_ALIAS} | cut -f 2 -d " ")
PUBLIC_KEY=$(tezos-client show address ${TZ_ALIAS} 2>/dev/null | grep "Public Key: " | awk '{print $3}')

echo $body | pbcopy
echo signature $SIGNATURE
echo PUBLIC_KEY $PUBLIC_KEY

SECRET_URL_REQ=$(curl -s -X GET -d "nonce=${body}" -d "signature=${SIGNATURE}" -d "public_key=${PUBLIC_KEY}" http://localhost:8080/vending-machine)
echo $SECRET_URL_REQ
# SECRET_URL=$(curl -X POST -d "guid=${GUID}" -d "signature=${SIGNATURE}" -d "public_key=${PUBLIC_KEY}" https:/$CLUSTER_ADDRESS/vending-machine)

# echo $SIGNATURE
# echo $PUBLIC_KEY
# printf "URL: $SECRET_URL"
