FROM postgres:alpine
ENV POSTGRES_USER=tezos
ENV POSTGRES_DB=tezos
ENV POSTGRES_PASSWORD=tezosrocks
ADD schema.sql /docker-entrypoint-initdb.d/
