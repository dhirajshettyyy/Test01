#!/usr/bin/env bash
# Stop and remove the local ONIX test network's containers.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down
