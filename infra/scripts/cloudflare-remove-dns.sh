#!/usr/bin/env bash
set -euo pipefail

# Load the repo-root .env regardless of CWD (make targets cd into infra/pulumi
# first, so a bare `. .env` would miss it).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Preserve a caller-provided DRY_RUN so the .env default doesn't clobber it.
_DRY_RUN_CALLER="${DRY_RUN:-}"
if [ -f "$REPO_ROOT/.env" ]; then
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
fi
if [ -n "$_DRY_RUN_CALLER" ]; then
  DRY_RUN="$_DRY_RUN_CALLER"
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required. Install: brew install jq"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }

: "${CF_API_TOKEN:?CF_API_TOKEN must be set (see .env.example)}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set (see .env.example)}"
: "${CF_API_RECORD_NAME:?CF_API_RECORD_NAME must be set (see .env.example)}"
: "${CF_WORKER_RECORD_NAME:?CF_WORKER_RECORD_NAME must be set (see .env.example)}"

CF_API="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"

# Bound every Cloudflare API call so a stalled connection can't hang the script.
CURL_OPTS=(--connect-timeout 10 --max-time 30)

# delete_record TYPE NAME
delete_record() {
  local type="$1" name="$2"

  local record_id
  record_id=$(curl -s "${CURL_OPTS[@]}" -X GET "$CF_API?type=$type&name=$name" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
    | jq -r '.result[0].id // empty')

  if [ -z "$record_id" ]; then
    echo "No $type record found for $name"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "DRY RUN: would delete $type record $name (id $record_id)"
    return 0
  fi

  local result
  result=$(curl -s "${CURL_OPTS[@]}" -X DELETE "$CF_API/$record_id" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

  if [ "$(echo "$result" | jq -r '.success // false')" = "true" ]; then
    echo "Deleted $type record $name"
  else
    echo "Cloudflare API returned an error deleting $type $name:" >&2
    echo "$result" | jq -r '.errors[]?.message // (.messages // "unknown error")' >&2
    exit 1
  fi
}

printf "Preparing to remove Cloudflare records %s, %s\n" "$CF_API_RECORD_NAME" "$CF_WORKER_RECORD_NAME"

delete_record "A" "$CF_API_RECORD_NAME"
delete_record "AAAA" "$CF_WORKER_RECORD_NAME"
