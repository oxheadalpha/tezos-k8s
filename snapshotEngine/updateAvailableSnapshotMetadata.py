from genericpath import exists
import os
import urllib, json
import urllib.request

allSubDomains = os.environ['ALL_SUBDOMAINS'].split(",")

filename="snapshots.json"

# Write empty top-level array to initialize json
json_object = []

# Get each subdomain's base.json and combine all artifacts into 1 metadata file
for subDomain in allSubDomains:
  with urllib.request.urlopen("https://"+subDomain+".xtz-shots.io/base.json") as url:
    data = json.loads(url.read().decode())
    for entry in data:
      json_object.append(entry)

# Write to file
with open (filename, 'w') as json_file:
  json_string = json.dumps(json_object, indent=4)
  json_file.write(json_string)