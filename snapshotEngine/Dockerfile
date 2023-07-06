FROM jekyll/jekyll:4.2.0

ENV GLIBC_VER=2.31-r0

# Install python/pip
ENV PYTHONUNBUFFERED=1
ENV KUBECTL_VERSION=v1.24.3

ARG TARGETARCH

#
# Installs lz4, jq, yq, kubectl, and awscliv2, and python3
#
RUN apk --no-cache add \
        binutils \
        curl \
        lz4 \
        'jq<1.6-r1'  \
        bash \
    && echo "Arch: ${TARGETARCH}" \
    && wget -q -O /usr/bin/yq $(wget -q -O - https://api.github.com/repos/mikefarah/yq/releases/latest \
        | jq -r --arg YQ_ARCH "yq_linux_${TARGETARCH}" '.assets[] | select(.name == $YQ_ARCH) | .browser_download_url') \
    && chmod +x /usr/bin/yq \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin \
    && curl -sL https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub -o /etc/apk/keys/sgerrand.rsa.pub \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-${GLIBC_VER}.apk \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-bin-${GLIBC_VER}.apk \
    && curl -sLO https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-i18n-${GLIBC_VER}.apk \
    && apk add --no-cache \
        glibc-${GLIBC_VER}.apk \
        glibc-bin-${GLIBC_VER}.apk \
        glibc-i18n-${GLIBC_VER}.apk \
    && /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8 \
    && curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && aws/install \
    && rm -rf \
        awscliv2.zip \
        aws \
        /usr/local/aws-cli/v2/*/dist/aws_completer \
        /usr/local/aws-cli/v2/*/dist/awscli/data/ac.index \
        /usr/local/aws-cli/v2/*/dist/awscli/examples \
        glibc-*.apk \
    && apk --no-cache del \
        binutils \
    && rm -rf /var/cache/apk/* \
    && apk add --update --no-cache python3-dev && ln -sf python3 /usr/bin/python \
    && python3 -m ensurepip \
    && pip3 install --no-cache-dir --upgrade pip && \
       pip3 install --no-cache-dir setuptools boto3 datefinder datetime pytz jsonschema==4.17.3

RUN chown jekyll:jekyll -R /usr/gem

# TODO: Make file structure organized like  with /scripts and /templates
# We install gemfile here to save time on website build in zip-and-upload
WORKDIR /snapshot-website-base
COPY --chown=jekyll:jekyll snapshot-website-base/Gem* /
RUN bundle install
WORKDIR /
COPY . /
RUN chown -R jekyll:jekyll /snapshot-website-base

ENTRYPOINT ["/entrypoint.sh"]
