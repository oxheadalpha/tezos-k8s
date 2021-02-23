FROM tezos/tezos:master
ENV PYTHONUNBUFFERED=1
RUN sudo apk add --no-cache --virtual .build-deps jq gcc py3-pip python3-dev musl-dev libffi-dev make \
     && pip install base58 pynacl
COPY entrypoint.py /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
