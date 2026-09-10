#!/usr/bin/env bash
# Stop processes started by native-run.sh (onix-bap, onix-bpp, the sandbox
# stubs). Leaves redis-server running since other things may depend on it;
# pass --all to also stop redis.
set -euo pipefail
cd "$(dirname "$0")/.."
pidfile=".native/pids"

if [ -f "$pidfile" ]; then
  while read -r pid name; do
    [ -z "${pid:-}" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null && echo "stopped $name (pid $pid)"
    fi
  done < "$pidfile"
  rm -f "$pidfile"
else
  echo "No .native/pids file found - nothing to stop."
fi

if [ "${1:-}" = "--all" ]; then
  redis-cli -p 6379 shutdown nosave 2>/dev/null && echo "stopped redis-server" || true
fi
