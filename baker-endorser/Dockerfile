FROM registry.gitlab.com/nomadic-labs/tezos:amd64-florencenet-docker
RUN sudo apk add jq bash
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
