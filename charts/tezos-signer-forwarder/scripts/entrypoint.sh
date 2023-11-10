#!/bin/sh

/usr/sbin/sshd -D -e -p ${TUNNEL_ENDPOINT_PORT}
