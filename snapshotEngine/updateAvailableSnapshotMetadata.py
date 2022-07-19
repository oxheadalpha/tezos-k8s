from genericpath import exists
import os
import urllib, json
import urllib.request
import boto3
import sys

allSubDomains = os.environ['ALL_SUBDOMAINS']

# Iterate over each subDomain/base.json and append to snapshot.json
filename = "snapshots.json"
with open (filename, "w") as json_file:
  json.dump("[]",json_file)

if not exists(filename):
  sys.exit('##### ERROR '+filename+' does not exist! #####')

with open (filename, 'w') as json_file:
  for subDomain in allSubDomains:
    # Existing list in snapshots.json
    existingData = json.load(json_file)
    # URL to current network metadata file
    url = "https://"+subDomain+"xtz-shots.io/base.json"
    # Parse json and turn into list
    response = urllib.request.urlopen(url)
    data = json.loads(response.read())
    # Add new data to new list object
    existingData.append(data)
    # Add to snapshots.json
    json.dump(existingData, json_file)

if not os.path.getsize(filename) > 3:
  sys.exit('##### ERROR '+filename+' is not greater than 3 bytes! #####')

# Upload to S3 bucket
s3 = boto3.resource('s3')
BUCKET = os.environ['S3_BUCKET']
s3.Bucket(BUCKET).upload_file(filename, filename)