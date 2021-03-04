import * as pulumi from "@pulumi/pulumi";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";
import * as awsx from "@pulumi/awsx";

import * as fs from 'fs';
import * as YAML from 'yaml'

const repo = new awsx.ecr.Repository("tezos-k8s");

// Manual step: create a pulumi_values.yaml in the top level dir
// with mkchain command:
//   mkchain pulumi
//

const chainName = "fbetanet"

const defaultHelmValuesFile = fs.readFileSync("../charts/tezos/values.yaml", 'utf8')
const defaultHelmValues = YAML.parse(defaultHelmValuesFile)

const helmValuesFile = fs.readFileSync('florencenobanet.yaml', 'utf8')
const helmValues = YAML.parse(helmValuesFile)

const tezosK8sImages = defaultHelmValues["tezos_k8s_images"]
const pulumiTaggedImages = Object.entries(tezosK8sImages).reduce(
    (obj, [key]) => {
	obj[key] = repo.buildAndPushImage(`../${key.replace(/_/g, "-")}`)
	return obj
    },
    {}
)

helmValues["tezos_k8s_images"] = pulumiTaggedImages

const vpc = new awsx.ec2.Vpc(chainName + "-vpc", {});

// For now, we set the number of EKS nodes to be the number of
// Tezos bakers/nodes divided by 12.  We should fix this to
// be a little more automagic.  Why 12?  It's a guess currently,
// we should experiment a little to get a better number.  We add
// three because that's the minimum.

const numBakers = helmValues.nodes?.baking?.length || 0
const numRegularNodes  = helmValues.nodes?.regular?.length || 0

const totalTezosNodes = numBakers + numRegularNodes
const desiredClusterCapacity = Math.round(totalTezosNodes / 12 + 3);

// Create an EKS cluster.
const cluster = new eks.Cluster(chainName + "-chain", {
    vpcId: vpc.id,
    subnetIds: vpc.publicSubnetIds,
    instanceType: "t3.xlarge",
    desiredCapacity: desiredClusterCapacity,
    minSize: 3,
    maxSize: 100,
})

// private key for the baker inside the topo for both networks
const private_baking_key = fs.readFileSync('private_baking_key', 'utf8');

// private key for the bootstrap account with a lot of funds for both networks
const private_non_baking_key = fs.readFileSync('private_non_baking_key', 'utf8');

const nsFlorence = new k8s.core.v1.Namespace("fbeta", {metadata: {name:"fbeta",}},
					      { provider: cluster.provider});
export const nsNameFlorence = nsFlorence.metadata.name;

const helmValuesFlorenceFile = fs.readFileSync('florencenet.yaml', 'utf8')
const helmValuesFlorence = YAML.parse(helmValuesFlorenceFile)
helmValuesFlorence["accounts"].unshift({
    "name": "baker0",
    "key": private_baking_key,
    "type": "secret",
    "bootstrap_baker": true,
    "bootstrap_balance": 2500000000000});
helmValuesFlorence["accounts"].push({
    "name": "TQFree",
    "key": private_non_baking_key,
    "type": "secret",
    "bootstrap_baker": false,
    "bootstrap_balance": 50000000000000});


helmValuesFlorence["tezos_k8s_images"] = pulumiTaggedImages
// Deploy Tezos into our cluster.
const chain = new k8s.helm.v2.Chart("chain", {
    namespace: nsNameFlorence,
    path: "../charts/tezos",
    values: helmValuesFlorence,
}, { providers: { "kubernetes": cluster.provider } });

const nsFlorenceNoBa = new k8s.core.v1.Namespace("fbetanoba", {metadata: {name:"fbetanoba",}},
					      { provider: cluster.provider});
export const nsNameFlorenceNoBa = nsFlorenceNoBa.metadata.name;

const helmValuesFlorenceNoBaFile = fs.readFileSync('florencenobanet.yaml', 'utf8')
const helmValuesFlorenceNoBa = YAML.parse(helmValuesFlorenceNoBaFile)
helmValuesFlorenceNoBa["accounts"].unshift({
    "name": "baker0",
    "key": private_baking_key,
    "type": "secret",
    "bootstrap_baker": true,
    "bootstrap_balance": 2500000000000});
helmValuesFlorenceNoBa["accounts"].push({
    "name": "TQFree",
    "key": private_non_baking_key,
    "type": "secret",
    "bootstrap_baker": false,
    "bootstrap_balance": 50000000000000});
helmValuesFlorenceNoBa["tezos_k8s_images"] = pulumiTaggedImages

// Deploy Tezos into our cluster.
const chainNoBa = new k8s.helm.v2.Chart("chainNoBa", {
    namespace: nsNameFlorenceNoBa,
    path: "../charts/tezos",
    values: helmValuesFlorenceNoBa,
}, { providers: { "kubernetes": cluster.provider } });

// Manual steps after all is done:
// Enable proxy protocol v2 on the target groups:
//   https://github.com/kubernetes/ingress-nginx/issues/5051#issuecomment-685736696
// Create a A record in the dns domain for which a certificate was created.

// Export the cluster's kubeconfig.
export const kubeconfig = cluster.kubeconfig;
export const clusterName = cluster.eksCluster.name;
