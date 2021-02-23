FROM tezos/tezos:master
RUN sudo apk add jq netcat-openbsd
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
