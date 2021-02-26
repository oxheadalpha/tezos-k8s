FROM tezos/tezos:master_328bc6c3_20210215194506
ENV PYTHONUNBUFFERED=1
RUN sudo apk add --no-cache --virtual .build-deps jq gcc py3-pip python3-dev musl-dev libffi-dev make \
     && pip install base58 pynacl
COPY entrypoint.py /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
