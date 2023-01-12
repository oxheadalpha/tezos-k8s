#!/usr/bin/env python
import os
from flask import Flask, request, jsonify
import requests

import logging
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

application = Flask(__name__)

readiness_probe_path = os.getenv("READINESS_PROBE_PATH")

@application.route('/metrics', methods=['GET'])
def prometheus_metrics():
    '''
    Prometheus endpoint
    '''
    try:
        probe = requests.get(f"http://localhost:8443{readiness_probe_path}")
    except requests.exceptions.RequestException:
        probe = None
    return f'''# number of unhealthy signers - should be 0 or 1
unhealthy_signers_total {0 if probe else 1}
'''

if __name__ == "__main__":
   application.run(host = "0.0.0.0", port = 31732, debug = False)
