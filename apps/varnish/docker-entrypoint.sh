#!/bin/sh
set -e

# Get the backend host from environment or use default
BACKEND_HOST=${BACKEND_HOST:-api}
PURGE_TOKEN=${PURGE_TOKEN:-test-purge-token}

echo "Configuring Varnish with backend: $BACKEND_HOST and purge token: $PURGE_TOKEN"
# Generate VCL from template to /tmp
sed "s/BACKEND_HOST/$BACKEND_HOST/g; s/PURGE_TOKEN/$PURGE_TOKEN/g" /etc/varnish/default.vcl.template > /tmp/default.vcl

echo "Starting Varnish..."
exec varnishd -F -f /tmp/default.vcl -a http=0.0.0.0:80,HTTP -a http=[::]:80,HTTP -p default_ttl=120
