FROM alpine:3.11

ENV GLIBC_VER=2.31-r0

RUN apk --no-cache add \
        binutils \
        curl \
        jq  \
    && wget -q -O /usr/bin/yq $(wget -q -O - https://api.github.com/repos/mikefarah/yq/releases/latest \
        | jq -r '.assets[] | select(.name == "yq_linux_amd64") | .browser_download_url') \
    && chmod +x /usr/bin/yq \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin

COPY . /

ENTRYPOINT ["/entrypoint.sh"]