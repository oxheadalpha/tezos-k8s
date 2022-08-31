from genericpath import exists
import os
import urllib, json
import urllib.request

allSubDomains = os.environ['ALL_SUBDOMAINS'].split(",")
snapshotWebsiteBaseDomain = os.environ['SNAPSHOT_WEBSITE_DOMAIN_NAME']

filename="snapshots.json"

# Write empty top-level array to initialize json
json_object = []

print(allSubDomains)

# Get each subdomain's base.json and combine all artifacts into 1 metadata file
for subDomain in allSubDomains:
  baseJsonUrl="https://"+subDomain+"."+snapshotWebsiteBaseDomain+"/base.json"
  try:
    with urllib.request.urlopen(baseJsonUrl) as url:
      data = json.loads(url.read().decode())
      for entry in data:
        json_object.append(entry)
  except urllib.error.HTTPError:
    continue

# Write to file
with open (filename, 'w') as json_file:
  json_string = json.dumps(json_object, indent=4)
  json_file.write(json_string)