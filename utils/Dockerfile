FROM alpine
ENV PYTHONUNBUFFERED=1

# Note: we install build deps for pip, then remove everything after pip install.
RUN	apk add --no-cache --virtual .build-deps gcc py3-pip		\
				python3-dev musl-dev libffi-dev make	\
     && pip install base58 pynacl					\
     && apk del .build-deps						\
     && apk add jq netcat-openbsd curl python3 py3-pip

COPY commitment-params.json /
COPY config-generator.py /
COPY config-generator.sh /
COPY entrypoint.sh /
COPY snapshot-downloader.sh /
COPY wait-for-bootstrap.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
