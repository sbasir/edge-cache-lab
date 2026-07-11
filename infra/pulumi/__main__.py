"""A Python Pulumi program"""

import json
from typing import cast

import pulumi
import pulumi_aws as aws
from pulumi_aws import ec2, iam

from user_data import build_user_data
from utils import load_template_source

prefix = "edge-cache-lab"
config = pulumi.Config()
# set via: pulumi config set ami ami-0123456789abcdef --stack dev
ami_override = config.get("ami")
aws_region = aws.config.region or "false"

if not aws_region or aws_region == "false":
    raise ValueError("AWS region must be configured (e.g. 'me-central-1').")


# Build the IAM trust policy that allows EC2 to assume the role.
def build_assume_role_policy() -> str:
    """Return the assume-role policy JSON for EC2."""
    policy: dict[str, object] = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole",
            }
        ],
    }
    return json.dumps(policy)


# Build the Parameter Store policy that allows access.
def build_parameter_store_policy() -> str:
    """Return the Parameter Store policy JSON."""
    actions: list[str] = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "ssm:PutParameter",
    ]
    policy: dict[str, object] = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": actions,
                "Resource": "arn:aws:ssm:*:*:parameter/edge-cache-lab/*",
            }
        ],
    }
    return json.dumps(policy)


# -----------------------------------------------------------------------------
# IAM Role and Instance Profile for SSM and Parameter Store access
# -----------------------------------------------------------------------------

# IAM Role for the EC2 instance
ec2_role = iam.Role(
    f"{prefix}-role",
    name=f"{prefix}-role",
    assume_role_policy=build_assume_role_policy(),
    description=("IAM role for EC2 instance with SSM access"),
    tags={"Name": f"{prefix}-role"},
)

# Attach AWS managed policy for SSM Session Manager
_ssm_policy_attachment = iam.RolePolicyAttachment(
    f"{prefix}-ssm-policy",
    role=ec2_role.name,
    policy_arn="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
)

_cloudwatch_agent_policy_attachment = iam.RolePolicyAttachment(
    f"{prefix}-cloudwatch-agent-policy",
    role=ec2_role.name,
    policy_arn="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
)

# Custom policy for SSM Parameter Store access
_parameter_store_policy = iam.RolePolicy(
    f"{prefix}-parameter-store-policy",
    role=ec2_role.name,
    policy=build_parameter_store_policy(),
)

# Instance Profile to attach the role to EC2
ec2_instance_profile = iam.InstanceProfile(
    f"{prefix}-instance-profile",
    role=ec2_role.name,
    tags={"Name": f"{prefix}-instance-profile"},
)

# -----------------------------------------------------------------------------
# S3 Bucket for Bootstrap Scripts (to stay under cloud-init 16KB limit)
# -----------------------------------------------------------------------------

scripts_bucket = aws.s3.Bucket(
    f"{prefix}-scripts-bucket",
    tags={"Name": f"{prefix}-scripts-bucket"},
    versioning=aws.s3.BucketVersioningArgs(
        enabled=True,
    ),
)

# Configure server-side encryption for the bucket
_bucket_sse = aws.s3.BucketServerSideEncryptionConfiguration(
    f"{prefix}-scripts-bucket-sse",
    bucket=scripts_bucket.id,
    rules=[
        aws.s3.BucketServerSideEncryptionConfigurationRuleArgs(
            apply_server_side_encryption_by_default=aws.s3.BucketServerSideEncryptionConfigurationRuleApplyServerSideEncryptionByDefaultArgs(
                sse_algorithm="AES256",
            ),
        )
    ],
)

# Upload the Python/shell scripts that would otherwise bloat cloud-config
k3s_install_object = aws.s3.BucketObject(
    f"{prefix}-k3s-install-script",
    bucket=scripts_bucket.id,
    key="k3s-install.sh",
    content=load_template_source("k3s-install.sh"),
    content_type="text/x-sh",
)

validate_k3s_object = aws.s3.BucketObject(
    f"{prefix}-validate-k3s-script",
    bucket=scripts_bucket.id,
    key="validate-k3s.sh",
    content=load_template_source("validate-k3s.sh"),
    content_type="text/x-sh",
)

# IAM policy to allow EC2 instance to read scripts from S3
_scripts_bucket_policy = iam.RolePolicy(
    f"{prefix}-scripts-bucket-policy",
    role=ec2_role.name,
    policy=scripts_bucket.arn.apply(
        lambda arn: json.dumps(
            {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": ["s3:GetObject"],
                        "Resource": f"{arn}/*",
                    }
                ],
            }
        )
    ),
)

# -----------------------------------------------------------------------------
# Networking: VPC, Subnets, Internet Gateway, Route Table, Security Group
# -----------------------------------------------------------------------------

vpc = ec2.Vpc(
    f"{prefix}-vpc",
    cidr_block="10.11.0.0/16",
    assign_generated_ipv6_cidr_block=True,
    tags={"Name": f"{prefix}-vpc"},
)

igw = ec2.InternetGateway(
    f"{prefix}-igw",
    vpc_id=vpc.id,
    tags={"Name": f"{prefix}-igw"},
)

rt = ec2.RouteTable(
    f"{prefix}-rt",
    vpc_id=vpc.id,
    tags={"Name": f"{prefix}-rt"},
)

ipv4_route = ec2.Route(
    f"{prefix}-ipv4-route",
    route_table_id=rt.id,
    destination_cidr_block="0.0.0.0/0",
    gateway_id=igw.id,
)
ipv6_route = ec2.Route(
    f"{prefix}-ipv6-route",
    route_table_id=rt.id,
    destination_ipv6_cidr_block="::/0",
    gateway_id=igw.id,
)
availability_zones = aws.get_availability_zones()
az_1 = availability_zones.names[0]
az_2 = availability_zones.names[1]
az_3 = availability_zones.names[2]

public_subnet_1 = ec2.Subnet(
    f"{prefix}-public-subnet-{az_1}",
    vpc_id=vpc.id,
    cidr_block="10.11.1.0/24",
    ipv6_cidr_block=cast(
        pulumi.Input[str],
        vpc.ipv6_cidr_block.apply(
            lambda cidr: cidr.replace("00::/56", "01::/64") if cidr else None
        ),
    ),
    assign_ipv6_address_on_creation=True,
    availability_zone=az_1,
    tags={"Name": f"{prefix}-public-subnet-{az_1}"},
)
public_subnet_2 = ec2.Subnet(
    f"{prefix}-public-subnet-{az_2}",
    vpc_id=vpc.id,
    cidr_block="10.11.2.0/24",
    ipv6_cidr_block=cast(
        pulumi.Input[str],
        vpc.ipv6_cidr_block.apply(
            lambda cidr: cidr.replace("00::/56", "02::/64") if cidr else None
        ),
    ),
    assign_ipv6_address_on_creation=True,
    availability_zone=az_2,
    tags={"Name": f"{prefix}-public-subnet-{az_2}"},
)
public_subnet_3 = ec2.Subnet(
    f"{prefix}-public-subnet-{az_3}",
    vpc_id=vpc.id,
    cidr_block="10.11.3.0/24",
    ipv6_cidr_block=cast(
        pulumi.Input[str],
        vpc.ipv6_cidr_block.apply(
            lambda cidr: cidr.replace("00::/56", "03::/64") if cidr else None
        ),
    ),
    assign_ipv6_address_on_creation=True,
    availability_zone=az_3,
    tags={"Name": f"{prefix}-public-subnet-{az_3}"},
)
ec2.RouteTableAssociation(
    f"{prefix}-public-subnet-{az_1}-association",
    subnet_id=public_subnet_1.id,
    route_table_id=rt.id,
)
ec2.RouteTableAssociation(
    f"{prefix}-public-subnet-{az_2}-association",
    subnet_id=public_subnet_2.id,
    route_table_id=rt.id,
)
ec2.RouteTableAssociation(
    f"{prefix}-public-subnet-{az_3}-association",
    subnet_id=public_subnet_3.id,
    route_table_id=rt.id,
)

# Security group for Ec2 instance
ec2_sg = ec2.SecurityGroup(
    f"{prefix}-sg",
    description="Security group for Spot Instance",
    vpc_id=vpc.id,
    tags={"Name": f"{prefix}-sg"},
)

# Ingress: HTTP (80) for API access (IPv4)
_api_ingress_ipv4 = ec2.SecurityGroupRule(
    f"{prefix}-ingress-ipv4",
    type="ingress",
    from_port=80,
    to_port=80,
    protocol="tcp",
    cidr_blocks=["0.0.0.0/0"],
    security_group_id=ec2_sg.id,
    description="API HTTP port (IPv4)",
)

# Ingress: HTTP (80) for API access (IPv6)
_api_ingress_ipv6 = ec2.SecurityGroupRule(
    f"{prefix}-ingress-ipv6",
    type="ingress",
    from_port=80,
    to_port=80,
    protocol="tcp",
    ipv6_cidr_blocks=["::/0"],
    security_group_id=ec2_sg.id,
    description="API HTTP port (IPv6)",
)

# Egress: Allow all outbound traffic (required for SSM, package updates, etc.)
ec2.SecurityGroupRule(
    f"{prefix}-egress-all",
    type="egress",
    from_port=0,
    to_port=0,
    protocol="-1",
    cidr_blocks=["0.0.0.0/0"],
    security_group_id=ec2_sg.id,
    description="Allow all outbound traffic",
)

# Egress: Allow all outbound traffic (IPv6)
ec2.SecurityGroupRule(
    f"{prefix}-egress-all-ipv6",
    type="egress",
    from_port=0,
    to_port=0,
    protocol="-1",
    ipv6_cidr_blocks=["::/0"],
    security_group_id=ec2_sg.id,
    description="Allow all outbound traffic (IPv6)",
)

# -----------------------------------------------------------------------------
# EC2 Spot Instance for k3s Server
# -----------------------------------------------------------------------------

if ami_override:
    ami = ec2.get_ami(
        filters=[{"name": "image-id", "values": [ami_override]}],
    )
else:
    ami = ec2.get_ami(
        most_recent=True,
        owners=["amazon"],
        filters=[
            {"name": "name", "values": ["al2023-ami-2023*-arm64"]},
            {"name": "virtualization-type", "values": ["hvm"]},
            {"name": "root-device-type", "values": ["ebs"]},
            {"name": "architecture", "values": ["arm64"]},
        ],
    )

# Create the Spot Instance Request
spot = ec2.SpotInstanceRequest(
    f"{prefix}-spot",
    ami=ami.id,
    instance_type="t4g.small",  # Suitable ARM-based instance for k3s server
    iam_instance_profile=ec2_instance_profile.name,
    vpc_security_group_ids=[ec2_sg.id],
    subnet_id=public_subnet_2.id,
    associate_public_ip_address=True,
    ipv6_address_count=1,
    user_data=scripts_bucket.bucket.apply(
        lambda bucket_name: build_user_data(aws_region=aws_region, scripts_bucket=bucket_name)
    ),
    # Spot instance configuration
    spot_type="persistent",  # Keeps requesting if interrupted
    instance_interruption_behavior="stop",  # Stop instead of terminate on interruption
    wait_for_fulfillment=True,  # Wait for the spot request to be fulfilled
    # Use standard credit mode to avoid burst charges
    credit_specification={"cpu_credits": "standard"},
    # Metadata options for IMDSv2 (more secure)
    metadata_options={
        "http_endpoint": "enabled",
        "http_tokens": "required",  # Require IMDSv2
        "http_put_response_hop_limit": 1,
    },
    # Root volume configuration
    root_block_device={
        "volume_type": "gp3",
        "volume_size": 8,
        "delete_on_termination": True,
        "encrypted": True,
    },
    tags={
        "Name": f"{prefix}-spot",
        "Purpose": "Edge Cache Lab k8s Server",
    },
    opts=pulumi.ResourceOptions(depends_on=[scripts_bucket]),
)

ec2.Tag(
    f"{prefix}-spot-name-tag",
    resource_id=spot.spot_instance_id,
    key="Name",
    value=f"{prefix}-spot-instance",
    opts=pulumi.ResourceOptions(depends_on=[spot]),
)

# Allocate an Elastic IP so the public IP remains stable across reboots.
ec2_eip = ec2.Eip(
    f"{prefix}-eip",
    domain="vpc",
    instance=spot.spot_instance_id,
    opts=pulumi.ResourceOptions(depends_on=[igw]),
    tags={"Name": f"{prefix}-eip"},
)

# Associate the EIP with the Spot Instance when the instance ID is ready.
ec2.EipAssociation(
    f"{prefix}-eip-assoc",
    instance_id=spot.spot_instance_id,
    allocation_id=ec2_eip.allocation_id,
)

# Export useful information
pulumi.export("spot_request_id", spot.id)
pulumi.export("ami_id", ami.id)
pulumi.export("ami_name", ami.name)
pulumi.export("instance_id", spot.spot_instance_id)
pulumi.export("public_ip", ec2_eip.public_ip)
pulumi.export("eip_allocation_id", ec2_eip.allocation_id)
pulumi.export("security_group_id", ec2_sg.id)
pulumi.export("iam_role_arn", ec2_role.arn)
pulumi.export("scripts_bucket_name", scripts_bucket.bucket)

# SSM Session Manager connect command
pulumi.export(
    "ssm_connect_command",
    spot.spot_instance_id.apply(
        lambda id: f"aws ssm start-session --target {id} --region {aws_region}"
    ),
)
