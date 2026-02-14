#!/bin/sh
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUTPUT_FILE="$SCRIPT_DIR/../../infra/k8s/base/varnish/default.vcl"
BACKEND_HOST=${BACKEND_HOST:-edge-cache-api}
PURGE_TOKEN=${PURGE_TOKEN:-test-purge-token}

sed "s/BACKEND_HOST/$BACKEND_HOST/g; s/PURGE_TOKEN/$PURGE_TOKEN/g" "$SCRIPT_DIR/default.vcl.template" > "$OUTPUT_FILE"
