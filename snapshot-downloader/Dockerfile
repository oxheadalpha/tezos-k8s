FROM registry.gitlab.com/nomadic-labs/tezos:amd64-florencenet-docker
RUN sudo apk add curl lz4 xz jq
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
