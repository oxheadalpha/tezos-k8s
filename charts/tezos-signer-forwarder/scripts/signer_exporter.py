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
endpoint_alias = os.getenv("ENDPOINT_ALIAS")
baker_alias = os.getenv("BAKER_ALIAS")
signer_metrics = os.getenv("SIGNER_METRICS") == "true"

def relabel(prometheus_metrics,extra_labels):
    '''
    Add labels to existing prometheus_metrics
    '''
    relabeled_metrics = ""
    for line in prometheus_metrics.splitlines():
        if line.startswith("#"):
            relabeled_metrics += line + "\n"
        else:
            if "{" in line:
                # line has labels 
                labeled_line = re.sub(r'{(.*)}', r'{\1,%s}' % extra_labels, line)
            else:
                labeled_line = re.sub(r'(.*) ', r'\1{%s} ' % extra_labels, line)
            relabeled_metrics += labeled_line + "\n"
    return relabeled_metrics

@application.route('/metrics', methods=['GET'])
def prometheus_metrics():
    '''
    Prometheus endpoint
    Combines the readiness probe URL (i.e. checks that ledger is configured)
    and the health probe (check power status for example)
    '''
    extra_labels = 'midl_endpoint_alias="%s",midl_baker_alias="%s"' % (endpoint_alias, baker_alias)

    try:
        probe = requests.get(f"http://localhost:{signer_port}{readiness_probe_path}")
    except requests.exceptions.RequestException:
        probe = None
    if probe and signer_metrics:
        try:
            healthz = relabel(requests.get(f"http://localhost:{signer_port}/healthz").text, extra_labels)
        except requests.exceptions.RequestException:
            healthz = None
    else:
        healthz = None
    return '''# number of unhealthy signers - should be 0 or 1
unhealthy_signers_total{%s} %s
%s''' % (extra_labels, 0 if probe else 1, healthz or "")

if __name__ == "__main__":
   application.run(host = "0.0.0.0", port = 31732, debug = False)
