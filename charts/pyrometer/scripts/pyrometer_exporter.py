#!/usr/bin/env python
from flask import Flask, request, jsonify
import requests
import datetime

import logging

log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)

application = Flask(__name__)

unhealthy_bakers = set()


@application.route("/pyrometer_webhook", methods=["POST"])
def pyrometer_webhook():
    """
    Receive all events from pyrometer
    """
    for msg in request.get_json():
        if msg["kind"] == "baker_unhealthy":
            print(f"Baker {msg['baker']} is unhealthy")
            unhealthy_bakers.add(msg["baker"])
        if msg["kind"] == "baker_recovered":
            print(f"Baker {msg['baker']} recovered")
            unhealthy_bakers.remove(msg["baker"])

    return "Webhook received"


@application.route("/metrics", methods=["GET"])
def prometheus_metrics():
    """
    Prometheus endpoint
    """
    return f"""# total number of monitored bakers that are currently unhealthy
pyrometer_unhealthy_bakers_total {len(unhealthy_bakers)}
"""


if __name__ == "__main__":
    application.run(host="0.0.0.0", port=31732, debug=False)
