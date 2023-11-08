#! /usr/bin/env python
from flask import Flask
import requests
from requests.exceptions import ConnectTimeout, ReadTimeout, RequestException
import datetime

import logging

log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)

application = Flask(__name__)

AGE_LIMIT_IN_SECS = 600
# https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
# Default readiness probe timeoutSeconds is 1s, timeout sync request before that and return a
# connect timeout error if necessary
NODE_CONNECT_TIMEOUT = 0.9

@application.route("/is_synced")
def sync_checker():
    # Fail sidecar on purpose
    return "Fail sidecar on purpose", 500

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=31732, debug=False)
