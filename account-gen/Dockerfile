FROM python:alpine
ENV PYTHONUNBUFFERED=1


RUN     apk add --no-cache gcc g++ python3-dev libffi-dev musl-dev make git libsodium-dev libsecp256k1-dev gmp-dev

COPY requirements.txt /

RUN pip install -r requirements.txt

COPY account_gen.py /

ENTRYPOINT ["/account_gen.py"]

CMD []
