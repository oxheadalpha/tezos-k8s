FROM python:3.9-alpine
ENV PYTHONUNBUFFERED=1

#
# Note: we install build deps for pip, then remove everything after
# pip install.
#
# We re-install binutils at the end because Python execve(2)s ld(1) to
# load zeromq.

RUN     apk add --no-cache --virtual .build-deps gcc g++ python3-dev	\
				libffi-dev musl-dev make		\
     && apk add libsodium-dev libsecp256k1-dev gmp-dev			\
     && apk add zeromq-dev						\
     && pip install base58 pynacl					\
     && pip install pytezos requests                                    \
     && apk del .build-deps						\
     && apk add jq netcat-openbsd curl binutils

COPY config-generator.py /
COPY config-generator.sh /
COPY entrypoint.sh /
COPY logger.sh /
COPY snapshot-downloader.sh /
COPY wait-for-bootstrap.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
