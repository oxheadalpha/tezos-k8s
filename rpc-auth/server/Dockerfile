FROM python:3.9 AS base

# Creating Application Source Code Directory
RUN mkdir -p /var/rpc-auth/

# Setting Home Directory for containers
WORKDIR /var/rpc-auth/

# Install dependencies for pytezos
RUN apt-get update
RUN apt-get install -y libsodium-dev libsecp256k1-dev libgmp-dev

# Installing python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copying src code to Container
COPY index.py .

# Application Environment variables
ENV PYTHONUNBUFFERED=x

# Exposing Ports
EXPOSE 8080

FROM base AS dev
ENV FLASK_ENV=development
CMD ["python3", "index.py"]

FROM base AS prod
ENV FLASK_ENV=production
CMD ["uwsgi", \
  "--http-socket", "0.0.0.0:8080", \
  "--callable", "app", \
  "--threads", "100", \
  "--processes", "1", \
  "--wsgi-file", "/var/rpc-auth/index.py", \
  "--py-autoreload", "3", \
  "--worker-reload-mercy", "0"]
