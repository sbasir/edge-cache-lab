# Pulumi Infrastructure for edge-cache-lab

Automates AWS infrastructure for k3s cluster running edge-cache-lab.

## Prerequisites

* Pulumi CLI (`brew install pulumi` or https://www.pulumi.com/docs/install/)
* AWS CLI configured with credentials
* Node.js 18+

## Quick Start

```sh
# From repository root
cd infra/pulumi

# Install dependencies
npm install

# Initialize stack (first time only)
pulumi stack init dev

# Configure AWS region
pulumi config set aws:region us-east-1

# Preview changes
pulumi preview

# Deploy infrastructure
pulumi up

# View outputs
pulumi stack output

# Teardown infrastructure
pulumi destroy
```

## Makefile Integration

From the repository root:

```sh
# Deploy infrastructure
make infra-up

# View infrastructure status
make infra-status

# Destroy infrastructure
make infra-down

# Get SSM connect command
make infra-ssm-connect
```

## What Gets Provisioned

* VPC with IPv4/IPv6 support
* Public subnet, Internet Gateway, Route Table
* Security Group (allows 443, 80, 6443 ingress; SSM for management)
* IAM Role with SSM and Parameter Store access
* S3 bucket for bootstrap scripts
* EC2 Spot Instance (t4g.small, Amazon Linux 2023 ARM64)
* Elastic IP for stable addressing
* Automated k3s installation
* Automated edge-cache-lab deployment

## Instance Access

### SSM Session Manager (recommended)

```sh
# Get connect command from Pulumi output
pulumi stack output ssmConnectCommand

# Or use Makefile
make infra-ssm-connect
```

### Kubectl Access

The kubeconfig is stored in SSM Parameter Store:

```sh
# Retrieve and configure kubectl
$(pulumi stack output kubectlSetupCommand)

# Or use Makefile
make infra-kubeconfig

# Then use kubectl
kubectl get nodes
kubectl -n edge-cache-api get all
```

### Varnish Endpoint

```sh
# Get Varnish HTTP endpoint
pulumi stack output varnishEndpoint

# Test the endpoint
curl $(pulumi stack output varnishEndpoint)/health
```

## Configuration

### Custom AMI

```sh
pulumi config set ami ami-0123456789abcdef
```

### AWS Region

```sh
pulumi config set aws:region us-west-2
```

## Cost Optimization

* Uses t4g.small spot instance (~$0.0042/hr, ~$3/month)
* Spot instance configured as "persistent" with "stop" on interruption
* Elastic IP maintained for stable addressing

## Scripts

Bootstrap scripts uploaded to S3:

* `k3s_install.sh` - Installs k3s cluster, kubectl, helm
* `deploy_edge_cache.sh` - Deploys edge-cache-lab to k3s

## Outputs

Key outputs available via `pulumi stack output`:

* `publicIp` - Elastic IP address
* `instanceId` - EC2 instance ID
* `ssmConnectCommand` - SSM Session Manager command
* `kubectlSetupCommand` - Command to configure kubectl
* `varnishEndpoint` - HTTP endpoint for Varnish
