#!/usr/bin/env bash
# Send a (possibly edited) sample payload through a running local ONIX
# adapter and print the response.
#
# Usage:
#   scripts/send-payload.sh <endpoint> <payload-file>
#
# <endpoint> is one of:
#   bap-caller:discover   bap-caller:confirm   bap-caller:status
#   bpp-caller:on_discover  bpp-caller:on_confirm  bpp-caller:on_status
#   bpp-caller:catalog/publish
#
# Examples:
#   scripts/send-payload.sh bap-caller:discover payloads/agri-schemes/search.json
#   scripts/send-payload.sh bap-caller:confirm  payloads/agri-schemes/confirm.json
#
# The adapter logs (docker compose logs -f onix-bap onix-bpp, or the files
# under .native/logs/ for the native runner) show the mapper's transformed
# output, the signature, and where the request was routed - that's the
# part worth watching while you iterate on an edited payload.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <endpoint> <payload-file>" >&2
  echo "  endpoint examples: bap-caller:discover, bap-caller:confirm, bap-caller:status," >&2
  echo "                     bpp-caller:on_discover, bpp-caller:on_confirm, bpp-caller:on_status," >&2
  echo "                     bpp-caller:catalog/publish" >&2
  exit 1
fi

endpoint="$1"
payload_file="$2"

module="${endpoint%%:*}"
action="${endpoint#*:}"

case "$module" in
  bap-caller) base_url="http://localhost:8081/bap/caller" ;;
  bap-receiver) base_url="http://localhost:8081/bap/receiver" ;;
  bpp-caller) base_url="http://localhost:8082/bpp/caller" ;;
  bpp-receiver) base_url="http://localhost:8082/bpp/receiver" ;;
  *)
    echo "Unknown module '$module' (expected bap-caller, bap-receiver, bpp-caller or bpp-receiver)" >&2
    exit 1
    ;;
esac

if [ ! -f "$payload_file" ]; then
  echo "Payload file not found: $payload_file" >&2
  exit 1
fi

url="${base_url}/${action}"
echo "POST ${url}"
echo "---"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

http_code=$(curl -sS -X POST "$url" \
  -H "Content-Type: application/json" \
  -d @"$payload_file" \
  -o "$response_file" \
  -w "%{http_code}")

if command -v jq >/dev/null 2>&1 && jq . "$response_file" >/dev/null 2>&1; then
  jq . "$response_file"
else
  cat "$response_file"
  echo
fi

echo "---"
echo "HTTP ${http_code}"
