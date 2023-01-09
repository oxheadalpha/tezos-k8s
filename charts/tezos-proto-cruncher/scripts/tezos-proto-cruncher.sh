apk add parallel
pip install boto3

python /proto-downloader.py

# Launch one process per CPU core to maximize utilization
num_cores=$(grep -c ^processor /proc/cpuinfo)
seq $num_cores | parallel --ungroup python /proto-cruncher.py /${PROTO_NAME}
