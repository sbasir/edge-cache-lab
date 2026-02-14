#!/bin/bash
set -ex

echo "[edge-cache-lab] Deploying edge-cache-lab to k3s..."

# Wait for k3s to be ready
echo "[edge-cache-lab] Waiting for k3s API to be ready..."
MAX_WAIT=60
elapsed=0
while ! kubectl get nodes &>/dev/null; do
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[edge-cache-lab] ERROR: k3s API not ready after ${MAX_WAIT}s"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

echo "[edge-cache-lab] k3s API is ready"

# Clone the repository or use local copy if available
REPO_URL="${EDGE_CACHE_REPO_URL:-https://github.com/sbasir/edge-cache-lab.git}"
REPO_BRANCH="${EDGE_CACHE_REPO_BRANCH:-main}"
WORK_DIR="/home/ec2-user/edge-cache-lab"

if [ ! -d "$WORK_DIR" ]; then
    echo "[edge-cache-lab] Cloning repository..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$WORK_DIR"
else
    echo "[edge-cache-lab] Repository already exists, pulling latest..."
    cd "$WORK_DIR" && git pull || true
fi

cd "$WORK_DIR"

# Build the API Docker image locally (k3s will use it)
echo "[edge-cache-lab] Building API Docker image..."
docker build -t edge-cache-lab-api:local apps/api

# Import the image into k3s
echo "[edge-cache-lab] Importing image into k3s..."
docker save edge-cache-lab-api:local | k3s ctr images import -

# Generate Varnish VCL ConfigMap
echo "[edge-cache-lab] Generating Varnish VCL..."
BACKEND_HOST=edge-cache-api PURGE_TOKEN=test-purge-token ./apps/varnish/render-k8s-vcl.sh

# Apply Kubernetes manifests
echo "[edge-cache-lab] Applying Kubernetes manifests..."
kubectl apply -k infra/k8s/overlays/local

# Wait for deployments to be ready
echo "[edge-cache-lab] Waiting for deployments to be ready..."
kubectl -n edge-cache-api rollout status deployment/edge-cache-api --timeout=300s
kubectl -n edge-cache-api rollout status deployment/varnish --timeout=300s

echo "[edge-cache-lab] Deployment complete!"
echo "[edge-cache-lab] View resources: kubectl -n edge-cache-api get all"
