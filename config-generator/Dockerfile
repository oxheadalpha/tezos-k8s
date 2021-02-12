FROM python:alpine
ENV PYTHONUNBUFFERED=1
RUN apk add --no-cache --virtual .build-deps gcc musl-dev libffi-dev make \
     && pip install base58 pynacl \
     && apk del .build-deps gcc musl-dev libffi-dev make
COPY entrypoint.py /
ENTRYPOINT ["python", "/entrypoint.py"]
CMD []
