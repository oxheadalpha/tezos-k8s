from flask import Flask, escape, request
import requests
import datetime

import logging
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

application = Flask(__name__)

AGE_LIMIT_IN_SECS = 600

@application.route('/is_synced')
def sync_checker():
    '''
    Here we don't trust the /is_bootstrapped endpoint of
    tezos-node. We have seen it return true when the node is
    in a bad state (for example, some crashed threads)
    Instead, we query the head block and verify timestamp is
    not too old.
    '''
    try:
        r = requests.get('http://127.0.0.1:8732/chains/main/blocks/head/header')
    except requests.exceptions.RequestException as e:
        err = "Could not connect to node, %s" % repr(e), 500
        print(err)
        return err
    header = r.json()
    if header["level"] == 0:
        # when chain has not been activated, bypass age check
        # and return succesfully to mark as ready
        # otherwise it will never activate (activation uses rpc service)
        return "Chain has not been activated yet"
    timestamp = r.json()["timestamp"]
    block_age = datetime.datetime.utcnow() -  datetime.datetime.strptime(timestamp, '%Y-%m-%dT%H:%M:%SZ')
    age_in_secs = block_age.total_seconds()
    if age_in_secs > AGE_LIMIT_IN_SECS:
        err = "Error: Chain head is %s secs old, older than %s" % ( age_in_secs, AGE_LIMIT_IN_SECS), 500
        print(err)
        return err
    return "Chain is bootstrapped"

if __name__ == "__main__":
   application.run(host = "0.0.0.0", port = 31732, debug = False)
