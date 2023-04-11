set -eo pipefail
apk add py3-pip
pip install boto3

export PYTHONUNBUFFERED=1
python /tezos-proto-cruncher.py
