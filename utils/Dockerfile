FROM python:3.9-alpine
ENV PYTHONUNBUFFERED=1

# Note: we install build deps for pip, then remove everything after pip install.
RUN     apk add --no-cache --virtual .build-deps gcc python3-dev	\
				libffi-dev musl-dev make		\
     && pip install base58 pynacl					\
     && apk del .build-deps						\
     && apk add jq netcat-openbsd curl

COPY commitment-params.json /
COPY config-generator.py /
COPY config-generator.sh /
COPY entrypoint.sh /
COPY snapshot-downloader.sh /
COPY wait-for-bootstrap.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
