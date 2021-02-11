import * as pulumi from "@pulumi/pulumi";
import * as eks from "@pulumi/eks";
import * as k8s from "@pulumi/kubernetes";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";

import * as fs from 'fs';
import * as YAML from 'yaml'

const repo = new awsx.ecr.Repository("tezos-k8s");

// Manual step: create a pulumi_values.yaml in the top level dir
// with mkchain command:
//   mkchain pulumi
//

const chainName = pulumi.getStack();

const defaultHelmValuesFile = fs.readFileSync("../charts/tezos/values.yaml", 'utf8')
const defaultHelmValues = YAML.parse(defaultHelmValuesFile)

const helmValuesFile = fs.readFileSync(chainName + '_values.yaml', 'utf8')
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

function createWorkerNodeRole(name: string): aws.iam.Role {
    const managedPolicyArns: string[] = [
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    ];
    
    const role = new aws.iam.Role(name, {
        assumeRolePolicy: aws.iam.assumeRolePolicyForPrincipal({
            Service: "ec2.amazonaws.com",
        }),
    });

    let counter = 0;
    for (const policy of managedPolicyArns) {
        // RolePolicyAttachment is attached to the role upon instantiation, so
        // it doesn't need to be returned or assigned.
        const rpa = new aws.iam.RolePolicyAttachment(
            `${name}-policy-${counter++}`,
            { policyArn: policy, role: role },
        );
    }

    return role;
}

// Create an EKS cluster.
const resourceName = chainName + "-chain"
const cluster = new eks.Cluster(resourceName, {
    vpcId: vpc.id,
    subnetIds: vpc.publicSubnetIds,
    instanceType: "t3.xlarge",
    desiredCapacity: desiredClusterCapacity,
    minSize: 3,
    maxSize: 100,
    instanceRole: createWorkerNodeRole(resourceName),
})

const ns = new k8s.core.v1.Namespace("tezos", {metadata: {name:"tezos",}},
					      { provider: cluster.provider});
export const nsName = ns.metadata.name;

// Deploy Tezos into our cluster.
const chain = new k8s.helm.v2.Chart("chain", {
    namespace: nsName,
    path: "../charts/tezos",
    values: helmValues,
}, { providers: { "kubernetes": cluster.provider } });

if (false) {
    // change to true if you want rpc auth
    const nginxIngressHelmValues_file
	= fs.readFileSync('nginx_ingress_values.yaml', 'utf8')
    const nginxIngressHelmValues = YAML.parse(nginxIngressHelmValues_file)

    const rpc = new k8s.helm.v2.Chart("rpc-auth", {
	namespace: nsName,
	path: "../charts/rpc-auth",
	values: helmValues,
    }, { providers: { "kubernetes": cluster.provider } });

    // Manual step at this point:
    // * create a certificate
    // * put certificate arn in the nginx_ingress_values.yaml
    const nginxIngress = new k8s.helm.v2.Chart("nginx-ingress", {
	namespace: nsName,
	chart: "ingress-nginx",
	fetchOpts: {
	  repo: "https://kubernetes.github.io/ingress-nginx" },
	values: nginxIngressHelmValues,
    }, { providers: { "kubernetes": cluster.provider } });
}

// Manual steps after all is done:
// Enable proxy protocol v2 on the target groups:
//   https://github.com/kubernetes/ingress-nginx/issues/5051#issuecomment-685736696
// Create a A record in the dns domain for which a certificate was created.


// Create Cloudwatch namespace in EKS cluster
const amazonCloudwatchNamespace = new k8s.core.v1.Namespace("amazon-cloudwatch",
                                    {metadata: {name:"amazon-cloudwatch",}},
                                    {provider: cluster.provider});


// Create Fluent Bit configuration in EKS cluster
const clusterInfoConfigMap = new k8s.core.v1.ConfigMap("fluent-bit-cluster-info", {
    metadata: {
        name: "fluent-bit-cluster-info",
        namespace: "amazon-cloudwatch",
    },
    data: {
        "cluster.name": cluster.eksCluster.name,
        "http.server": "Off",
        "http.port": "",
        "read.head": "On",
        "read.tail": "Off",
        "logs.region": new pulumi.Config("aws").require("region"),
    },
}, {provider: cluster.provider});

// Deploy Fluent Bit DaemonSet to the EKS cluster
const fluentbit = new k8s.yaml.ConfigFile("fluent-bit", {file: "./fluent-bit.yaml"},
    {provider: cluster.provider}
);

// Export the cluster's kubeconfig.
export const kubeconfig = cluster.kubeconfig;
export const clusterName = cluster.eksCluster.name;
