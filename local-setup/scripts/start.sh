#!/usr/bin/env bash
# Bring up the local ONIX test network via Docker Compose.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Starting redis, onix-bap, onix-bpp, sandbox-bap, sandbox-bpp..."
docker compose up -d

echo
echo "Waiting for containers to become healthy..."
for i in $(seq 1 30); do
  if docker compose ps --format '{{.Health}}' 2>/dev/null | grep -qv "healthy\|^$" ; then
    :
  fi
  sleep 2
  if ! docker compose ps 2>/dev/null | grep -q "starting"; then
    break
  fi
done

docker compose ps

cat <<'EOF'

Endpoints:
  BAP caller   http://localhost:8081/bap/caller/<action>
  BAP receiver http://localhost:8081/bap/receiver/<on_action>
  BPP receiver http://localhost:8082/bpp/receiver/<action>
  BPP caller   http://localhost:8082/bpp/caller/<on_action>

Try it:
  scripts/send-payload.sh bap-caller:discover payloads/agri-schemes/search.json

Watch it happen:
  docker compose logs -f onix-bap onix-bpp

Stop everything:
  scripts/stop.sh
EOF
