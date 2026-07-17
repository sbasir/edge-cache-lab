#!/usr/bin/env bash
set -euo pipefail

# Load the repo-root .env regardless of CWD (make targets cd into infra/pulumi
# first so `pulumi stack output` resolves, so a bare `. .env` would miss it).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$REPO_ROOT/.env" ]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required. Install: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
command -v pulumi >/dev/null 2>&1 || { echo "pulumi is required"; exit 1; }

: "${CF_API_TOKEN:?CF_API_TOKEN must be set (see .env.example)}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set (see .env.example)}"
: "${CF_API_RECORD_NAME:?CF_API_RECORD_NAME must be set (see .env.example)}"
: "${CF_WORKER_RECORD_NAME:?CF_WORKER_RECORD_NAME must be set (see .env.example)}"
: "${CF_TTL:?CF_TTL must be set (see .env.example)}"
: "${CF_PROXIED:?CF_PROXIED must be set (see .env.example)}"

DRY_RUN_FLAG=0
if [ "${DRY_RUN:-0}" = "1" ]; then
  DRY_RUN_FLAG=1
fi

CF_API="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"

# upsert_record TYPE NAME CONTENT PROXIED
# Creates or updates a single DNS record, keyed on TYPE + NAME.
upsert_record() {
  local type="$1" name="$2" content="$3" proxied="$4"

  # Cloudflare requires ttl=1 ("automatic") for proxied records; only an
  # unproxied (DNS-only) record may carry an explicit TTL.
  local ttl="$CF_TTL"
  if [ "$proxied" = "true" ]; then
    ttl=1
  fi

  local record_id
  record_id=$(curl -s -X GET "$CF_API?type=$type&name=$name" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
    | jq -r '.result[0].id // empty')

  local payload
  payload=$(jq -n --arg type "$type" --arg name "$name" --arg content "$content" \
    --argjson ttl "$ttl" --argjson proxied "$proxied" \
    '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')

  if [ "$DRY_RUN_FLAG" -eq 1 ]; then
    echo "DRY RUN: would set $type $name -> $content (proxied=$proxied)"
    echo "  Payload: $payload"
    if [ -n "$record_id" ]; then
      echo "  Would update record id: $record_id"
    else
      echo "  Would create new record"
    fi
    return 0
  fi

  local result
  if [ -z "$record_id" ]; then
    echo "Creating $type record $name..."
    result=$(curl -s -X POST "$CF_API" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$payload")
  else
    echo "Updating $type record $name (id $record_id)..."
    result=$(curl -s -X PUT "$CF_API/$record_id" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "$payload")
  fi

  if [ "$(echo "$result" | jq -r '.success // false')" = "true" ]; then
    echo "  Cloudflare update successful"
  else
    echo "  Cloudflare API returned an error:" >&2
    echo "$result" | jq -r '.errors[]?.message // (.messages // "unknown error")' >&2
    exit 1
  fi
}

# --- API backend record: api.edge.<domain> -> origin public IP ---------------
PUBLIC_IP=$(pulumi stack output public_ip 2>/dev/null || true)
if [ -z "$PUBLIC_IP" ]; then
  echo "No public_ip found in stack outputs. Ensure stack is up." >&2
  exit 1
fi
upsert_record "A" "$CF_API_RECORD_NAME" "$PUBLIC_IP" "$CF_PROXIED"

# --- Worker route record: edge.<domain> --------------------------------------
# The SPA is served by a Cloudflare Worker route (edge.<domain>/*). A route only
# fires for a hostname that has a *proxied* DNS record in the zone, so we publish
# a placeholder AAAA pointing at the reserved discard prefix 100:: -- traffic is
# intercepted by the Worker before it is ever forwarded to this address.
upsert_record "AAAA" "$CF_WORKER_RECORD_NAME" "100::" "true"
