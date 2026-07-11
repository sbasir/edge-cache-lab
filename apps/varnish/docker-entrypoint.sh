#!/bin/sh
set -e

# Get the backend host from environment or use default
BACKEND_HOST=${BACKEND_HOST:-api}
PURGE_TOKEN=${PURGE_TOKEN:-test-purge-token}

echo "Configuring Varnish with backend: $BACKEND_HOST and purge token: [REDACTED]"
OUTPUT_DIR="/var/lib/varnish"
OUTPUT_FILE="$OUTPUT_DIR/default.vcl"
SOURCE_TEMPLATE="/etc/varnish/default.vcl.template"

mkdir -p "$OUTPUT_DIR"
sed "s/BACKEND_HOST/$BACKEND_HOST/g; s/PURGE_TOKEN/$PURGE_TOKEN/g" "$SOURCE_TEMPLATE" > "$OUTPUT_FILE"

echo "Starting Varnish..."
exec varnishd -F -f "$OUTPUT_FILE" -a "http=0.0.0.0:80,HTTP" -a "http=[::]:80,HTTP" -p default_ttl=120
