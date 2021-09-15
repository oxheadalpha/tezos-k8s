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
     && apk add git libsodium-dev libsecp256k1-dev gmp-dev			\
     && apk add zeromq-dev						\
     && pip install base58 pynacl					\
     && pip install pytezos requests                                    \
     && pip install pyblake2 pysodium numpy \
     && pip install -e 'git+https://github.com/vbuterin/pybitcointools.git@aeb0a2bbb8bbfe421432d776c649650eaeb882a5#egg=bitcoin' \
     && apk del .build-deps git \
     && apk add jq netcat-openbsd curl binutils \ 
     && apk add lz4

COPY config-generator.py /
COPY faucet-gen.py /
COPY config-generator.sh /
COPY entrypoint.sh /
COPY logger.sh /
COPY snapshot-downloader.sh /
COPY wait-for-bootstrap.sh /
COPY tarball_downloader.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
