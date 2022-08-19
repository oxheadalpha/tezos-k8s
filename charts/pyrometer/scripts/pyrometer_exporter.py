#!/usr/bin/env python
from flask import Flask, request, jsonify
import requests
import datetime

import logging
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

application = Flask(__name__)

@application.route('/pyrometer_webhook', methods=['POST'])
def pyrometer_webhook():
    '''
    Receive all events from pyrometer
    '''
    content = request.json
    print(content)
    return "Webhook received"

@application.route('/status', methods=['GET'])
def prometheus_status():
    '''
    Receive all events from pyrometer
    '''
    return jsonify("hi") 

if __name__ == "__main__":
   application.run(host = "0.0.0.0", port = 31732, debug = False)
