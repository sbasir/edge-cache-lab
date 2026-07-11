#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=infra/scripts/utils.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

INSTANCE_ID=${INSTANCE_ID:-}
OVERLAY_PATH=${OVERLAY_PATH:-}
API_IMAGE_URI=${API_IMAGE_URI:-}
VARNISH_IMAGE_URI=${VARNISH_IMAGE_URI:-}
IMAGE_TAG=${IMAGE_TAG:-}

# Parse CLI args (allow Makefile to pass --instance-id, --overlay-path, --api-image-uri, --varnish-image-uri, --image-tag)
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance-id|-i)
      INSTANCE_ID="$2"; shift 2;;
    --overlay-path|-o)
      OVERLAY_PATH="$2"; shift 2;;
    --api-image-uri)
      API_IMAGE_URI="$2"; shift 2;;
    --varnish-image-uri)
      VARNISH_IMAGE_URI="$2"; shift 2;;
    --image-tag)
      IMAGE_TAG="$2"; shift 2;;
    --help|-h)
      echo "Usage: $(basename "$0") --instance-id ID --overlay-path PATH --api-image-uri URI --varnish-image-uri URI --image-tag TAG";
      exit 0;;
    *)
      echo "Unknown argument: $1"; exit 1;;
  esac
done

missing=()
[ -z "$INSTANCE_ID" ] && missing+=("instance-id")
[ -z "$OVERLAY_PATH" ] && missing+=("overlay-path")
[ -z "$API_IMAGE_URI" ] && missing+=("api-image-uri")
[ -z "$VARNISH_IMAGE_URI" ] && missing+=("varnish-image-uri")
[ -z "$IMAGE_TAG" ] && missing+=("image-tag")
if [ ${#missing[@]} -ne 0 ]; then
  echo "❌ Missing required arguments: ${missing[*]}"
  echo "Usage: $(basename "$0") --instance-id ID --overlay-path PATH --api-image-uri URI --varnish-image-uri URI --image-tag TAG"
  exit 1
fi

command_exists aws
command_exists kubectl
command_exists kustomize

echo "Trying to connect using aws ssm start-session..."
SSM_PID=""
if nc_check "localhost" "6443"; then
    echo "   ✅ localhost:6443 is already reachable"
else
    echo "   ⏳ Starting SSM port forwarding session to localhost:6443..."
    aws ssm start-session \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters 'localPortNumber=6443,portNumber=6443' &
    SSM_PID=$!
    echo "   ✅ SSM port forwarding started with PID $SSM_PID"
    echo "   ⏳ Waiting for port forwarding to establish..."
    MAX_WAIT_SECONDS=10
    SLEEP_INTERVAL=1
    ELAPSED=0
    while ! nc_check "localhost" "6443"; do
        if [ "$ELAPSED" -ge "$MAX_WAIT_SECONDS" ]; then
            echo "❌ Still cannot reach localhost:6443 after ${MAX_WAIT_SECONDS}s of port forwarding"
            exit 1
        fi
        sleep "$SLEEP_INTERVAL"
        ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
    done
fi
PRIVATE_IP="localhost"
echo "   ✅ Connected to localhost:6443 via SSM port forwarding"

KUBECONFIG_B64=$(aws ssm get-parameter --name "/edge-cache-lab/k3s/kubeconfig" --with-decryption \
  --query 'Parameter.Value' --output text 2>/dev/null)

if [ -z "$KUBECONFIG_B64" ]; then
  echo "❌ Could not retrieve kubeconfig from SSM (/edge-cache-lab/k3s/kubeconfig)"
  exit 1
fi

TMP_DIR=$(mktemp -d)

KUBECONFIG_FILE="$TMP_DIR/kubeconfig"
echo "$KUBECONFIG_B64" | base64 -d > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
sed -E "s/127.0.0.1/$PRIVATE_IP/" "$KUBECONFIG_FILE" > "${KUBECONFIG_FILE}.tmp"
mv "${KUBECONFIG_FILE}.tmp" "$KUBECONFIG_FILE"

OVERLAY_DIR="$(pwd)/$OVERLAY_PATH"
KUSTOMIZATION_FILE="$OVERLAY_DIR/kustomization.yaml"
KUSTOMIZATION_BACKUP="$TMP_DIR/kustomization.yaml.bak"

cp "$KUSTOMIZATION_FILE" "$KUSTOMIZATION_BACKUP"

# Ensure cleanup: restore kustomization, stop SSM session, remove tmp dir
trap '
  if [ -f "$KUSTOMIZATION_BACKUP" ]; then
    cp "$KUSTOMIZATION_BACKUP" "$KUSTOMIZATION_FILE" || true
  fi
  if [ -n "$SSM_PID" ] && kill -0 "$SSM_PID" 2>/dev/null; then
    kill "$SSM_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
' EXIT

cd "$OVERLAY_DIR" || { echo "❌ Could not change directory to $OVERLAY_DIR"; exit 1; }
if ! kustomize edit set image "edge-cache-lab-api=${API_IMAGE_URI}:${IMAGE_TAG}"; then
  echo "❌ Failed to update kustomization with API image tag"
  exit 1
fi
if ! kustomize edit set image "edge-cache-lab-varnish=${VARNISH_IMAGE_URI}:${IMAGE_TAG}"; then
  echo "❌ Failed to update kustomization with Varnish image tag"
  exit 1
fi

# Apply kustomize overlay
kubectl --kubeconfig "$KUBECONFIG_FILE" apply -k "$OVERLAY_DIR"
kubectl --kubeconfig "$KUBECONFIG_FILE" rollout status deployment/api -n edge-cache-lab --timeout=60s
kubectl --kubeconfig "$KUBECONFIG_FILE" rollout status deployment/varnish -n edge-cache-lab --timeout=60s

echo "✅ Deployment complete (api: ${API_IMAGE_URI}:${IMAGE_TAG}, varnish: ${VARNISH_IMAGE_URI}:${IMAGE_TAG})"