import os
import urllib, json

allSubDomains = os.environ('ALL_SUBDOMAINS')

# Iterate over each subDomain/base.json and append to snapshot.json

for subDomain in allSubDomains:
  url = subDomain+"xtz-shots.io/base.json"
  response = urllib.urlopen(url)
  data = json.loads(response.read())