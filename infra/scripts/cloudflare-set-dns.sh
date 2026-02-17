#!/usr/bin/env bash
set -euo pipefail

# Load local .env if present
if [ -f .env ]; then
  # shellcheck disable=SC1091
  . .env
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required. Install: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v pulumi >/dev/null 2>&1 || { echo "pulumi is required"; exit 1; }

: "${CF_API_TOKEN:?CF_API_TOKEN must be set (see .env.example)}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set (see .env.example)}"
: "${CF_API_RECORD_NAME:?CF_API_RECORD_NAME must be set (see .env.example)}"
: "${CF_TTL:?CF_TTL must be set (see .env.example)}"
: "${CF_PROXIED:?CF_PROXIED must be set (see .env.example)}"

DRY_RUN_FLAG=0
if [ "${DRY_RUN:-0}" = "1" ]; then
  DRY_RUN_FLAG=1
fi

PUBLIC_IP=$(pulumi stack output public_ip 2>/dev/null || true)
if [ -z "$PUBLIC_IP" ]; then
  echo "No public_ip found in stack outputs. Ensure stack is up." >&2
  exit 1
fi

printf "Preparing to set Cloudflare record %s -> %s\n" "$CF_API_RECORD_NAME" "$PUBLIC_IP"

RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$CF_API_RECORD_NAME" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

PAYLOAD=$(jq -n --arg name "$CF_API_RECORD_NAME" --arg content "$PUBLIC_IP" --argjson ttl "$CF_TTL" --argjson proxied "$CF_PROXIED" \
  '{type: "A", name: $name, content: $content, ttl: $ttl, proxied: $proxied}')

if [ "$DRY_RUN_FLAG" -eq 1 ]; then
  echo "DRY RUN: would set Cloudflare record $CF_API_RECORD_NAME -> $PUBLIC_IP"
  echo "Payload: $PAYLOAD"
  if [ -n "$RECORD_ID" ]; then
    echo "Would update record id: $RECORD_ID"
  else
    echo "Would create new record"
  fi
  exit 0
fi

if [ -z "$RECORD_ID" ]; then
  echo "Creating DNS record..."
  result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$PAYLOAD")
else
  echo "Updating DNS record id $RECORD_ID..."
  result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$PAYLOAD")
fi

success=$(echo "$result" | jq -r '.success // false')
if [ "$success" = "true" ]; then
  echo "Cloudflare update successful"
  exit 0
else
  echo "Cloudflare API returned an error:" >&2
  echo "$result" | jq -r '.errors[]?.message // (.messages // "unknown error")' >&2
  exit 1
fi
