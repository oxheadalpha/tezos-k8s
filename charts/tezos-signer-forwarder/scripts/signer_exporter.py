#!/usr/bin/env python
import os
from flask import Flask, request, jsonify
import requests
import re

import logging
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

application = Flask(__name__)

readiness_probe_path = os.getenv("READINESS_PROBE_PATH")
signer_port = os.getenv("SIGNER_PORT")
signer_metrics = os.getenv("SIGNER_METRICS") == "true"

@application.route('/metrics', methods=['GET'])
def prometheus_metrics():
    '''
    Prometheus endpoint
    This combines:
    * the metrics from the signer, which themselves are a combination of the
      prometheus node-expoter and custom probes (power status, etc)
    * the `unhealthy_signers_total` metric exported by this script, verifying
      whether the signer URL configured upstream returns a 200 OK
    '''

    try:
        probe = requests.get(f"http://localhost:{signer_port}{readiness_probe_path}")
    except requests.exceptions.RequestException:
        probe = None
    if probe and signer_metrics:
        try:
            healthz = requests.get(f"http://localhost:{signer_port}/healthz").text
        except requests.exceptions.RequestException:
            healthz = None
    else:
        healthz = None
    return '''# number of unhealthy signers - should be 0 or 1
unhealthy_signers_total %s
%s''' % (0 if probe else 1, healthz or "")

if __name__ == "__main__":
   application.run(host = "0.0.0.0", port = 31732, debug = False)
