from genericpath import exists
import os
import urllib, json
from jsonschema import validate
from datetime import datetime

schemaURL = os.environ["SCHEMA_URL"]
allSubDomains = os.environ["ALL_SUBDOMAINS"].split(",")
s3Endpoint = "nyc3.digitaloceanspaces.com"
filename = "tezos-snapshots.json"

# Write empty top-level array to initialize json
artifact_metadata = []

urllib.request.urlretrieve(schemaURL, "schema.json")

print("Assembling global metadata file for all subdomains:")
print(allSubDomains)

# Get each subdomain's base.json and combine all artifacts into 1 metadata file
for subDomain in allSubDomains:
    baseJsonUrl = (
        "https://" + subDomain + "-shots" + "." + s3Endpoint + "/base.json"
    )
    try:
        with urllib.request.urlopen(baseJsonUrl) as url:
            data = json.loads(url.read().decode())
            for entry in data:
                artifact_metadata.append(entry)
    except urllib.error.HTTPError:
        continue

now = datetime.now()

# Matches octez block_timestamp.
# Is ISO 8601 with military offset of Z
dt_string = now.strftime('%Y-%m-%dT%H:%M:%SZ')

# Meta document that includes the list of storage artifacts among some other useful keys.
metadata_document = json.dumps({
    "date_generated": dt_string,
    "org": "Oxhead Alpha",
    "$schema": schemaURL,
    "data": artifact_metadata,
}, indent=4)

with open("schema.json","r") as f:
    schema = f.read()

# json.validate() returns None if successful
if not validate(json.loads(metadata_document), json.loads(schema)):
    print("Metadata successfully validated against schema!")
else:
    raise Exception("Metadata NOT validated against schema!")


# Write to file
with open(filename, "w") as json_file:
    json_file.write(metadata_document)

print(f"Done assembling global metadata file {filename}")
