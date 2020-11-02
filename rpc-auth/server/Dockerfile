FROM python:3.8-slim as builder

ARG FLASK_ENV=development

# Creating Application Source Code Directory
RUN mkdir -p /var/rpc-auth/

# Setting Home Directory for containers
WORKDIR /var/rpc-auth/

# Install dependencies for pytezos
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

COPY requirements.txt /var/rpc-auth/
RUN mkdir wheels \
        && pip wheel -r requirements.txt \
        --wheel-dir ./wheels --no-cache-dir

FROM python:3.8-slim

WORKDIR /var/rpc-auth/

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
COPY requirements.txt /var/rpc-auth/
RUN pip install -r requirements.txt \
        --no-index --find-links ./wheels \
        && rm -rf ./wheels

# Copying src code to Container
COPY index.py .

# Application Environment variables
ENV FLASK_ENV=$FLASK_ENV
ENV PYTHONUNBUFFERED=x

# Exposing Ports
EXPOSE 8080

# Running Python Application
CMD ["python3", "index.py"]
