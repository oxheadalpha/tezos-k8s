#!/bin/bash
set -x

#zerotier-one
cat <<EOF > /etc/supervisor/supervisord.conf
[supervisord]
[program:zerotier]
command=zerotier-one /var/tezos/zerotier
redirect_stdout=false
redirect_stderr=false
EOF
supervisord -c /etc/supervisor/supervisord.conf

[ ! -z $NETWORK_ID ] && { sleep 5; zerotier-cli -D/var/tezos/zerotier join $NETWORK_ID || exit 1; }

# waiting for Zerotier IP
# why 2? because you have an ipv6 and an a ipv4 address by default if everything is ok
IP_OK=0
while [ $IP_OK -lt 1 ]
do
  ZTDEV=$( ip addr | grep -i zt | grep -i mtu | awk '{ print $2 }' | cut -f1 -d':' | tail -1 )
  IP_OK=$( ip addr show dev $ZTDEV | grep -i inet | wc -l )
  sleep 5

  echo $IP_OK

  # # Auto accept the new client
  if [ $AUTOJOIN == "true"  ]
  then
    echo "Auto accept the new client"
    HOST_ID="$(zerotier-cli -D/var/tezos/zerotier info | awk '{print $3}')"
    curl -s -XPOST \
      -H "Authorization: Bearer $ZTAUTHTOKEN" \
      -d '{"hidden":"false","config":{"authorized":true}}' \
      "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"

#    # # If hostname is provided will be set
#    if [ ! -z $HOSTNAME ]
#    then
#      echo "Set hostname"
#      curl -s -XPOST \
#        -H "Authorization: Bearer $ZTAUTHTOKEN" \
#        -d "{\"name\":\"$ZTHOSTNAME\"}" \
#        "https://my.zerotier.com/api/network/$NETWORK_ID/member/$HOST_ID"
#    fi
  fi

  echo "Waiting for a ZeroTier IP on $ZTDEV interface... Accept the new host on my.zerotier.com"
done

zerotier-cli -D/var/tezos/zerotier -j listnetworks > /var/tezos/zerotier_data.json
