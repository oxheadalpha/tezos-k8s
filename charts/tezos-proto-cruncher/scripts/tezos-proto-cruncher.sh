set -eo pipefail
apk add parallel
pip install boto3

python /proto-downloader.py

if [ -z "${NUM_PARALLEL_PROCESSES}" ]; then
    # Launch one process per CPU core to maximize utilization
    NUM_PARALLEL_PROCESSES=$(grep -c ^processor /proc/cpuinfo)
fi
seq $NUM_PARALLEL_PROCESSES | parallel --ungroup python /proto-cruncher.py /${PROTO_NAME}
