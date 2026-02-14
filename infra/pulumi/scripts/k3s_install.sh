#!/bin/bash
set -ex

echo "[kubernetes] Installing k3s cluster..."

# Get private IP using IMDSv2 (required)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)

if [ -z "$PRIVATE_IP" ]; then
    echo "[kubernetes] ERROR: Could not retrieve private IP from metadata"
    exit 1
fi

echo "[kubernetes] Private IP: $PRIVATE_IP"

# Install iptables (required by k3s, not included by default in AL2023)
echo "[kubernetes] Installing iptables..."
dnf install -y iptables-legacy

# Make iptables the default (not nftables)
alternatives --set iptables /usr/sbin/iptables-legacy || true
alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# Install k3s with write-kubeconfig-mode to allow ec2-user to read it
echo "[kubernetes] Downloading and installing k3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644 --node-ip $PRIVATE_IP" sh -

# Wait for k3s service to stabilize (polling)
echo "[kubernetes] Waiting for k3s service to stabilize..."
MAX_WAIT="${K3S_STARTUP_TIMEOUT:-120}"
SLEEP_INTERVAL="${K3S_POLL_INTERVAL:-2}"
elapsed=0
while ! systemctl is-active --quiet k3s; do
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[kubernetes] ERROR: k3s failed to become active after ${MAX_WAIT}s"
        echo "[kubernetes] k3s service status:"
        systemctl status k3s || true
        echo "[kubernetes] k3s logs:"
        journalctl -u k3s --no-pager -n 50 || true
        exit 1
    fi
    sleep "$SLEEP_INTERVAL"
    elapsed=$((elapsed + SLEEP_INTERVAL))
done

echo "[kubernetes] k3s service is running (waited ${elapsed}s)"

# Configure kubectl for ec2-user and root
echo "[kubernetes] Configuring kubectl access..."

# Setup for ec2-user
mkdir -p /home/ec2-user/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
chown ec2-user:ec2-user /home/ec2-user/.kube/config
chmod 600 /home/ec2-user/.kube/config

# Setup for root (for administrative operations)
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chown root:root /root/.kube/config
chmod 600 /root/.kube/config

# Setup for ssm-user (if it exists)
if id -u ssm-user >/dev/null 2>&1; then
    mkdir -p /home/ssm-user/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ssm-user/.kube/config
    chown ssm-user:ssm-user /home/ssm-user/.kube/config
    chmod 600 /home/ssm-user/.kube/config
fi

# Update kubeconfigs to use private IP instead of localhost
sed -i "s/127.0.0.1/$PRIVATE_IP/g" /home/ec2-user/.kube/config
sed -i "s/127.0.0.1/$PRIVATE_IP/g" /root/.kube/config
if id -u ssm-user >/dev/null 2>&1; then
    sed -i "s/127.0.0.1/$PRIVATE_IP/g" /home/ssm-user/.kube/config
fi

# Store kubeconfig in SSM Parameter Store (SecureString)
echo "[kubernetes] Storing kubeconfig in SSM Parameter Store..."
if command -v aws &> /dev/null; then
    KUBECONFIG_B64=$(cat /etc/rancher/k3s/k3s.yaml | base64 -w0)
    aws ssm put-parameter \
        --name "/k3s/kubeconfig" \
        --value "$KUBECONFIG_B64" \
        --type SecureString \
        --overwrite 2>/dev/null || true
    echo "[kubernetes] Kubeconfig stored in SSM"
fi

# Store node token in SSM Parameter Store
echo "[kubernetes] Storing node token in SSM Parameter Store..."
if command -v aws &> /dev/null; then
    NODE_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
    aws ssm put-parameter \
        --name "/k3s/node-token" \
        --value "$NODE_TOKEN" \
        --type SecureString \
        --overwrite 2>/dev/null || true
    echo "[kubernetes] Node token stored in SSM"
fi

# Download and install kubectl
echo "[kubernetes] Installing kubectl..."
KUBECTL_URL="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
curl -LO "$KUBECTL_URL"
chmod 755 kubectl
mv kubectl /usr/local/bin/

# Download and install Helm
echo "[kubernetes] Installing helm..."
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
chmod 755 /usr/local/bin/helm || true

echo "[kubernetes] k3s installation complete"
