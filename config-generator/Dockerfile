FROM alpine
ENV PYTHONUNBUFFERED=1

# Note: we install build deps for pip, then remove everything after pip install.
# Then we reinstall runtime deps at the end.
RUN apk add --no-cache --virtual .build-deps gcc py3-pip python3-dev musl-dev libffi-dev make \
     && pip install base58 pynacl \
     && apk del .build-deps gcc musl-dev libffi-dev make \
     && apk add --no-cache --virtual install jq gcc python3 py3-pip \
     && apk add jq curl

COPY commitment-params.json /
COPY entrypoint.py /
COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
