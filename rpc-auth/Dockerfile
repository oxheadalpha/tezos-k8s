FROM python:3.9.6-slim as builder

RUN mkdir -p /var/rpc-auth/

WORKDIR /var/rpc-auth/

# Installing pytezos deps
RUN apt-get update -y \
  && apt-get install --no-install-recommends -y \
  automake \
  build-essential \
  libffi-dev \
  libgmp-dev \
  libsecp256k1-dev \
  libsodium-dev \
  libtool \
  pkg-config \
  && echo

COPY ./requirements.txt .
RUN mkdir wheels \
  && pip wheel -r requirements.txt \
  --wheel-dir ./wheels --no-cache-dir

FROM python:3.9-slim AS src

WORKDIR /var/rpc-auth/

# Installing pytezos deps
RUN apt-get update -y \
  && apt-get install --no-install-recommends -y \
  libffi-dev \
  libgmp-dev \
  libsecp256k1-dev \
  libsodium-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Installing python dependencies
COPY --from=builder /var/rpc-auth/wheels wheels
COPY ./requirements.txt .
RUN pip install -r requirements.txt \
  --no-index --find-links ./wheels \
  && rm -rf ./wheels ./requirements.txt

RUN groupadd -g 999 appuser && \
  useradd -r -u 999 -g appuser appuser

COPY --chown=appuser:appuser ./server/index.py .

ARG FLASK_ENV=production
ENV FLASK_ENV=$FLASK_ENV
ENV PYTHONUNBUFFERED=x

EXPOSE 8080

USER appuser

CMD uwsgi \
  --http-socket 0.0.0.0:8080 \
  --callable app \
  --threads 100 \
  --processes 1 \
  --wsgi-file index.py \
  --worker-reload-mercy 0 \
  $(if [ "${FLASK_ENV}" = "development" ] ; then echo "--touch-reload index.py" ; else : ; fi)
