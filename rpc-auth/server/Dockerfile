FROM python:3.8

ARG FLASK_ENV=development

# Creating Application Source Code Directory
RUN mkdir -p /var/rpc-auth/

# Setting Home Directory for containers
WORKDIR /var/rpc-auth/

# Install dependencies for pytezos
RUN apt-get update
RUN apt-get install -y libsodium-dev libsecp256k1-dev libgmp-dev

# Installing python dependencies
COPY requirements.txt /var/rpc-auth/
RUN pip install --no-cache-dir -r requirements.txt

# Copying src code to Container
COPY index.py /var/rpc-auth/

# Application Environment variables
ENV FLASK_ENV=$FLASK_ENV
ENV PYTHONUNBUFFERED=x

# Exposing Ports
EXPOSE 8080

# Running Python Application
CMD ["python3", "index.py"]
