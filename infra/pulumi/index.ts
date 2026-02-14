import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as fs from "fs";

const prefix = "edge-cache-k3s";
const config = new pulumi.Config();
const awsConfig = new pulumi.Config("aws");
const awsRegion = awsConfig.get("region") || "us-east-1";

// Allow AMI override via config
const amiOverride = config.get("ami");

// -----------------------------------------------------------------------------
// IAM Role and Instance Profile for SSM and Parameter Store access
// -----------------------------------------------------------------------------

const k3sRole = new aws.iam.Role(`${prefix}-role`, {
    name: `${prefix}-role`,
    assumeRolePolicy: JSON.stringify({
        Version: "2012-10-17",
        Statement: [{
            Effect: "Allow",
            Principal: { Service: "ec2.amazonaws.com" },
            Action: "sts:AssumeRole",
        }],
    }),
    description: "IAM role for k3s Spot Instance with SSM and Parameter Store access",
    tags: { Name: `${prefix}-role` },
});

// Attach AWS managed policy for SSM Session Manager
const ssmPolicyAttachment = new aws.iam.RolePolicyAttachment(`${prefix}-ssm-policy`, {
    role: k3sRole.name,
    policyArn: "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
});

// Custom policy for SSM Parameter Store read/write access
const parameterStorePolicy = new aws.iam.RolePolicy(`${prefix}-parameter-store-policy`, {
    role: k3sRole.name,
    policy: JSON.stringify({
        Version: "2012-10-17",
        Statement: [{
            Effect: "Allow",
            Action: [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
                "ssm:PutParameter",
            ],
            Resource: "*",
        }],
    }),
});

// Instance Profile to attach the role to EC2
const k3sInstanceProfile = new aws.iam.InstanceProfile(`${prefix}-instance-profile`, {
    role: k3sRole.name,
    tags: { Name: `${prefix}-instance-profile` },
});

// -----------------------------------------------------------------------------
// S3 Bucket for Bootstrap Scripts
// -----------------------------------------------------------------------------

const scriptsBucket = new aws.s3.Bucket(`${prefix}-scripts-bucket`, {
    tags: { Name: `${prefix}-scripts-bucket` },
});

// Upload k3s installation script
const k3sInstallScript = fs.readFileSync("./scripts/k3s_install.sh", "utf8");
const k3sInstallObject = new aws.s3.BucketObject(`${prefix}-k3s-install`, {
    bucket: scriptsBucket.id,
    key: "k3s_install.sh",
    content: k3sInstallScript,
    contentType: "text/x-shellscript",
});

// Upload edge-cache-lab deployment script
const deployEdgeCacheScript = fs.readFileSync("./scripts/deploy_edge_cache.sh", "utf8");
const deployEdgeCacheObject = new aws.s3.BucketObject(`${prefix}-deploy-edge-cache`, {
    bucket: scriptsBucket.id,
    key: "deploy_edge_cache.sh",
    content: deployEdgeCacheScript,
    contentType: "text/x-shellscript",
});

// IAM policy to allow EC2 instance to read scripts from S3
const scriptsBucketPolicy = new aws.iam.RolePolicy(`${prefix}-scripts-bucket-policy`, {
    role: k3sRole.name,
    policy: scriptsBucket.arn.apply(arn => JSON.stringify({
        Version: "2012-10-17",
        Statement: [{
            Effect: "Allow",
            Action: ["s3:GetObject"],
            Resource: `${arn}/*`,
        }],
    })),
});

// -----------------------------------------------------------------------------
// Networking: VPC, Subnets, Internet Gateway, Route Table, Security Group
// -----------------------------------------------------------------------------

const vpc = new aws.ec2.Vpc(`${prefix}-vpc`, {
    cidrBlock: "10.20.0.0/16",
    assignGeneratedIpv6CidrBlock: true,
    tags: { Name: `${prefix}-vpc` },
});

const igw = new aws.ec2.InternetGateway(`${prefix}-igw`, {
    vpcId: vpc.id,
    tags: { Name: `${prefix}-igw` },
});

const rt = new aws.ec2.RouteTable(`${prefix}-rt`, {
    vpcId: vpc.id,
    tags: { Name: `${prefix}-rt` },
});

const ipv4Route = new aws.ec2.Route(`${prefix}-ipv4-route`, {
    routeTableId: rt.id,
    destinationCidrBlock: "0.0.0.0/0",
    gatewayId: igw.id,
});

const ipv6Route = new aws.ec2.Route(`${prefix}-ipv6-route`, {
    routeTableId: rt.id,
    destinationIpv6CidrBlock: "::/0",
    gatewayId: igw.id,
});

// Get availability zones
const availabilityZones = aws.getAvailabilityZones({});

const publicSubnet = new aws.ec2.Subnet(`${prefix}-public-subnet`, {
    vpcId: vpc.id,
    cidrBlock: "10.20.1.0/24",
    ipv6CidrBlock: vpc.ipv6CidrBlock.apply(cidr => 
        cidr ? cidr.replace("00::/56", "01::/64") : ""
    ),
    assignIpv6AddressOnCreation: true,
    availabilityZone: availabilityZones.then(azs => azs.names[0]),
    tags: { Name: `${prefix}-public-subnet` },
});

const rtAssociation = new aws.ec2.RouteTableAssociation(`${prefix}-public-subnet-association`, {
    subnetId: publicSubnet.id,
    routeTableId: rt.id,
});

// Security group for k3s instance
const k3sSg = new aws.ec2.SecurityGroup(`${prefix}-sg`, {
    description: "Security group for k3s Spot Instance",
    vpcId: vpc.id,
    tags: { Name: `${prefix}-sg` },
});

// Ingress: HTTPS (443) for k3s API access (IPv4)
const k3sApiIngressIpv4 = new aws.ec2.SecurityGroupRule(`${prefix}-ingress-k3s-api-ipv4`, {
    type: "ingress",
    fromPort: 443,
    toPort: 443,
    protocol: "tcp",
    cidrBlocks: ["0.0.0.0/0"],
    securityGroupId: k3sSg.id,
    description: "k3s API HTTPS (IPv4)",
});

// Ingress: HTTP (80) for Varnish access (IPv4)
const varnishIngressIpv4 = new aws.ec2.SecurityGroupRule(`${prefix}-ingress-varnish-ipv4`, {
    type: "ingress",
    fromPort: 80,
    toPort: 80,
    protocol: "tcp",
    cidrBlocks: ["0.0.0.0/0"],
    securityGroupId: k3sSg.id,
    description: "Varnish HTTP (IPv4)",
});

// Ingress: k3s API (6443) for remote kubectl access (IPv4)
const k3sApiAltIngressIpv4 = new aws.ec2.SecurityGroupRule(`${prefix}-ingress-k3s-6443-ipv4`, {
    type: "ingress",
    fromPort: 6443,
    toPort: 6443,
    protocol: "tcp",
    cidrBlocks: ["0.0.0.0/0"],
    securityGroupId: k3sSg.id,
    description: "k3s API alt port (IPv4)",
});

// Egress: Allow all outbound traffic (IPv4)
const egressAllIpv4 = new aws.ec2.SecurityGroupRule(`${prefix}-egress-all-ipv4`, {
    type: "egress",
    fromPort: 0,
    toPort: 0,
    protocol: "-1",
    cidrBlocks: ["0.0.0.0/0"],
    securityGroupId: k3sSg.id,
    description: "Allow all outbound traffic (IPv4)",
});

// Egress: Allow all outbound traffic (IPv6)
const egressAllIpv6 = new aws.ec2.SecurityGroupRule(`${prefix}-egress-all-ipv6`, {
    type: "egress",
    fromPort: 0,
    toPort: 0,
    protocol: "-1",
    ipv6CidrBlocks: ["::/0"],
    securityGroupId: k3sSg.id,
    description: "Allow all outbound traffic (IPv6)",
});

// -----------------------------------------------------------------------------
// User Data (cloud-init)
// -----------------------------------------------------------------------------

function buildUserData(bucketName: string): string {
    return `#!/bin/bash
set -ex

echo "[init] Starting k3s + edge-cache-lab bootstrap..."

# Download and execute k3s installation script from S3
aws s3 cp s3://${bucketName}/k3s_install.sh /tmp/k3s_install.sh
chmod +x /tmp/k3s_install.sh
/tmp/k3s_install.sh

# Download and execute edge-cache-lab deployment script from S3
aws s3 cp s3://${bucketName}/deploy_edge_cache.sh /tmp/deploy_edge_cache.sh
chmod +x /tmp/deploy_edge_cache.sh
/tmp/deploy_edge_cache.sh

echo "[init] Bootstrap complete!"
`;
}

// -----------------------------------------------------------------------------
// EC2 Spot Instance for k3s
// -----------------------------------------------------------------------------

// Get AMI (Amazon Linux 2023 ARM64)
const ami = amiOverride 
    ? aws.ec2.getAmi({
        filters: [{ name: "image-id", values: [amiOverride] }],
    })
    : aws.ec2.getAmi({
        mostRecent: true,
        owners: ["amazon"],
        filters: [
            { name: "name", values: ["al2023-ami-2023*-arm64"] },
            { name: "virtualization-type", values: ["hvm"] },
            { name: "root-device-type", values: ["ebs"] },
            { name: "architecture", values: ["arm64"] },
        ],
    });

// Create the Spot Instance Request
const k3sSpot = new aws.ec2.SpotInstanceRequest(`${prefix}-spot`, {
    ami: ami.then(a => a.id),
    instanceType: "t4g.small", // Sufficient for k3s + edge-cache-lab
    iamInstanceProfile: k3sInstanceProfile.name,
    vpcSecurityGroupIds: [k3sSg.id],
    subnetId: publicSubnet.id,
    associatePublicIpAddress: true,
    ipv6AddressCount: 1,
    userData: scriptsBucket.bucket.apply(bucket => buildUserData(bucket)),
    
    // Spot instance configuration
    spotType: "persistent", // Keeps requesting if interrupted
    instanceInterruptionBehavior: "stop", // Stop instead of terminate on interruption
    waitForFulfillment: true, // Wait for the spot request to be fulfilled
    
    // Use standard credit mode to avoid burst charges
    creditSpecification: {
        cpuCredits: "standard",
    },
    
    // Metadata options for IMDSv2 (more secure)
    metadataOptions: {
        httpEndpoint: "enabled",
        httpTokens: "required", // Require IMDSv2
        httpPutResponseHopLimit: 1,
    },
    
    // Root volume configuration
    rootBlockDevice: {
        volumeType: "gp3",
        volumeSize: 20, // Increased for k3s and container images
        deleteOnTermination: true,
        encrypted: true,
    },
    
    tags: {
        Name: `${prefix}-k3s`,
        Purpose: "k3s cluster for edge-cache-lab",
    },
}, { dependsOn: [scriptsBucket] });

// Tag the instance (spot instances require separate tag resource)
const k3sSpotNameTag = new aws.ec2.Tag(`${prefix}-spot-name-tag`, {
    resourceId: k3sSpot.spotInstanceId,
    key: "Name",
    value: `${prefix}-k3s`,
});

// -----------------------------------------------------------------------------
// Elastic IP
// -----------------------------------------------------------------------------

const k3sEip = new aws.ec2.Eip(`${prefix}-eip`, {
    domain: "vpc",
    instance: k3sSpot.spotInstanceId,
    tags: { Name: `${prefix}-eip` },
}, { dependsOn: [igw] });

const k3sEipAssociation = new aws.ec2.EipAssociation(`${prefix}-eip-assoc`, {
    instanceId: k3sSpot.spotInstanceId,
    allocationId: k3sEip.allocationId,
});

// -----------------------------------------------------------------------------
// Stack Outputs
// -----------------------------------------------------------------------------

export const spotRequestId = k3sSpot.id;
export const instanceId = k3sSpot.spotInstanceId;
export const publicIp = k3sEip.publicIp;
export const eipAllocationId = k3sEip.allocationId;
export const publicDns = k3sSpot.publicDns;
export const securityGroupId = k3sSg.id;
export const iamRoleArn = k3sRole.arn;
export const scriptsBucketName = scriptsBucket.bucket;
export const amiId = ami.then(a => a.id);
export const amiName = ami.then(a => a.name);

// SSM Session Manager connect command
export const ssmConnectCommand = pulumi.interpolate`aws ssm start-session --target ${k3sSpot.spotInstanceId} --region ${awsRegion}`;

// Kubectl access via SSM (retrieve kubeconfig from Parameter Store)
export const kubectlSetupCommand = pulumi.interpolate`aws ssm get-parameter --name /k3s/kubeconfig --with-decryption --region ${awsRegion} --query Parameter.Value --output text | base64 -d > ~/.kube/edge-cache-k3s.config && export KUBECONFIG=~/.kube/edge-cache-k3s.config`;

// Varnish endpoint
export const varnishEndpoint = pulumi.interpolate`http://${k3sEip.publicIp}`;
