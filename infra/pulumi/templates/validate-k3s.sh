#!/bin/bash
# infra/pulumi/templates/validate-k3s.sh
# Validates deployment: API + k3s

set -e

echo ""
echo "════════════════════════════════════════════════"
echo "  Validation: API + k3s"
echo "════════════════════════════════════════════════"
echo ""

# 1. k3s service
echo "1. ✓ k3s service status:"
if systemctl is-active --quiet k3s; then
    echo "   ✅ k3s systemd service is running"
else
    echo "   ❌ k3s systemd service is not running"
    echo "   Logs: journalctl -u k3s --no-pager -n 50"
fi

# 2. kubectl
echo "2. ✓ Kubernetes API connectivity:"
if kubectl cluster-info &> /dev/null; then
    echo "   ✅ kubectl can reach API"
else
    echo "   ❌ kubectl cannot reach API"
fi

# 3. Nodes
echo "3. ✓ Kubernetes node status:"
NODES=$(kubectl get nodes -o json | jq '.items | length')
READY=$(kubectl get nodes -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l)
echo "   Nodes: ${NODES}, Ready: ${READY}"
if [ "$NODES" -eq "$READY" ]; then
    echo "   ✅ All nodes Ready"
else
    echo "   ⚠️  Some nodes not ready:"
    kubectl get nodes
fi

# 4. Ports
echo "4. ✓ Listening ports:"
echo "   Port 3000 (API):"
ss -tlnp | grep ":3000 " | echo "   ✅ Listening" || echo "   ⚠️  Not listening"

echo "   Port 6443 (k3s API):"
ss -tlnp | grep ":6443 " | echo "   ✅ Listening" || echo "   ⚠️  Not listening"

# 5. SSM parameters
echo "5. ✓ SSM Parameter Store:"
if command -v aws &> /dev/null; then
    if aws ssm get-parameter --name "/k3s/kubeconfig" --query "Parameter.Version" --output text 2>/dev/null | grep -q .; then
        echo "   ✅ kubeconfig in SSM"
    else
        echo "   ⚠️  kubeconfig not in SSM"
    fi

    if aws ssm get-parameter --name "/k3s/node-token" --query "Parameter.Version" --output text 2>/dev/null | grep -q .; then
        echo "   ✅ node-token in SSM"
    else
        echo "   ⚠️  node-token not in SSM"
    fi
else
    echo "   ⚠️  AWS CLI not available"
fi

# 6. Applications
echo "6. ✓ Applications:"
READY=$(kubectl get pods -n edge-cache-lab -o json | jq '.items[] | select(.metadata.labels.app=="api") | select(.status.conditions[] | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l)
if [ "1" -eq "$READY" ]; then
    echo "   ✅ Application running"
else
    echo "   ❌ Application not running: deploy with 'make k8s-remote-up' or GitHub Actions"
fi

# 7. Deployments
echo "7. ✓ Current k3s deployments:"
kubectl get deployments --all-namespaces 2>/dev/null || echo "   ❌ No deployments found"

echo ""
echo "════════════════════════════════════════════════"
echo "  ✅ Validation Complete"
echo "════════════════════════════════════════════════"
echo ""
