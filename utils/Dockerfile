FROM python:3.9-alpine
ENV PYTHONUNBUFFERED=1

#
# Note: we install build deps for pip, then remove everything after
# pip install.  We also add `--no-cache` to pip and apk to reduce the
# size of the generated image.
#
# We re-install binutils at the end because Python execve(2)s ld(1) to
# load zeromq.

RUN     PIP="pip --no-cache install"					\
        APK_ADD="apk add --no-cache";					\
        $APK_ADD --virtual .build-deps gcc python3-dev			\
				libffi-dev musl-dev make		\
     && $APK_ADD libsodium-dev libsecp256k1-dev gmp-dev			\
     && $APK_ADD zeromq-dev						\
     && $PIP install base58 pynacl					\
     && $PIP install mnemonic pytezos requests				\
     && $PIP install pyblake2 pysodium flask \
     && apk del .build-deps \
     && $APK_ADD jq netcat-openbsd curl binutils \
     && $APK_ADD lz4

COPY config-generator.py /
COPY faucet-gen.py /
COPY config-generator.sh /
COPY entrypoint.sh /
COPY logger.sh /
COPY sidecar.py /
COPY snapshot-downloader.sh /
COPY wait-for-dns.sh /
ENTRYPOINT ["/entrypoint.sh"]
CMD []
