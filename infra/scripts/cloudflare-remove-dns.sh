#!/usr/bin/env bash
set -euo pipefail

# Load local .env if present
if [ -f .env ]; then
  # shellcheck disable=SC1091
  . .env
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required. Install: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }

: "${CF_API_TOKEN:?CF_API_TOKEN must be set (see .env.example)}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set (see .env.example)}"
: "${CF_API_RECORD_NAME:?CF_API_RECORD_NAME must be set (see .env.example)}"

printf "Preparing to remove Cloudflare record %s\n" "$CF_API_RECORD_NAME"

RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$CF_API_RECORD_NAME" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" | jq -r '.result[0].id // empty')

if [ -z "$RECORD_ID" ]; then
  echo "No DNS record found for $CF_API_RECORD_NAME"
  exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY RUN: would delete record id $RECORD_ID"
  exit 0
fi

result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

success=$(echo "$result" | jq -r '.success // false')
if [ "$success" = "true" ]; then
  echo "Cloudflare delete successful"
  exit 0
else
  echo "Cloudflare API returned an error:" >&2
  echo "$result" | jq -r '.errors[]?.message // (.messages // "unknown error")' >&2
  exit 1
fi
