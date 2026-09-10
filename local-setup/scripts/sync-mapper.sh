#!/usr/bin/env bash
# Pull the latest V2 mapper from the upstream beckn-v2-migration-docs repo
# and drop it into config/mappings.yaml, per that repo's own
# mappings-v2/Instructions.md ("Step 2: Update the Mapper File"). Restart
# the adapters afterwards to pick it up (ONIX only reads the mapper at
# startup).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching latest beckn-v2-migration-docs..."
git clone --depth 1 https://github.com/abhey-WIL/beckn-v2-migration-docs.git "$tmp/repo"

cp "$tmp/repo/mappings-v2/mappings/mappings.yaml" config/mappings.yaml
echo "Updated config/mappings.yaml"

# Keep the vendored reference copy in sync too, if it exists in this repo.
if [ -d "../beckn-v2-migration-docs" ]; then
  cp -r "$tmp/repo/mappings-v2" "$tmp/repo/mappings" "$tmp/repo/configs" "$tmp/repo/sample-payloads" ../beckn-v2-migration-docs/
  echo "Updated ../beckn-v2-migration-docs vendored copy"
fi

echo
echo "Restart the adapters to pick up the new mapper:"
echo "  docker compose restart onix-bap onix-bpp   # or scripts/native-stop.sh && scripts/native-run.sh"
