#!/usr/bin/env bash
# Fallback for environments where Docker Hub image pulls aren't reachable
# (this was true of the sandbox this repo was built in - see ../README.md).
# Builds beckn-onix from source with Go and runs everything as plain
# processes on localhost instead of containers: redis, onix-bap (:8081),
# onix-bpp (:8082), and two minimal Python stub apps standing in for
# sandbox-bap (:3001) / sandbox-bpp (:3002) - they log what they receive
# and ACK, but unlike the real fidedocker/sandbox-2.0 image used by
# docker-compose.yml, they do not auto-generate on_* responses. Use
# scripts/start.sh (Docker Compose) instead if you can reach Docker Hub -
# it gives you the real sandbox apps and a fully automatic round trip.
#
# Usage: scripts/native-run.sh
# Stop:  scripts/native-stop.sh

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
NATIVE_DIR="$ROOT/.native"
ONIX_SRC="$NATIVE_DIR/beckn-onix"
ONIX_REPO="https://github.com/beckn/beckn-onix.git"

command -v go >/dev/null 2>&1 || { echo "go is required (see go.mod in $ONIX_SRC for the version)" >&2; exit 1; }
command -v redis-server >/dev/null 2>&1 || { echo "redis-server is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for the sandbox stubs" >&2; exit 1; }

mkdir -p "$NATIVE_DIR/logs" "$NATIVE_DIR/bap/config" "$NATIVE_DIR/bpp/config"

# --- 1. Fetch + build beckn-onix (server + plugins) -----------------------
if [ ! -d "$ONIX_SRC" ]; then
  echo "Cloning beckn-onix..."
  git clone --depth 1 "$ONIX_REPO" "$ONIX_SRC"
fi

if [ ! -x "$NATIVE_DIR/onix-server" ]; then
  echo "Building beckn-onix server (go build)..."
  (cd "$ONIX_SRC" && go build -o "$NATIVE_DIR/onix-server" cmd/adapter/main.go)
fi

if [ ! -d "$ONIX_SRC/plugins" ] || [ -z "$(ls -A "$ONIX_SRC/plugins" 2>/dev/null)" ]; then
  echo "Building beckn-onix plugins (this downloads a lot of Go modules the first time)..."
  chmod +x "$ONIX_SRC/install/build-plugins.sh" "$ONIX_SRC/install/scripts/version-vars.sh" 2>/dev/null || true
  (cd "$ONIX_SRC" && ./install/build-plugins.sh)
fi

# --- 2. Generate localhost-flavoured config copies -------------------------
# The committed config/ uses Docker Compose service names (redis, onix-bap,
# onix-bpp, sandbox-bap, sandbox-bpp) as hostnames. Regenerate a copy with
# those replaced by 127.0.0.1 + the same ports, so the same config/ stays
# the single source of truth for both run modes.
for role in bap bpp; do
  rm -rf "$NATIVE_DIR/$role/config"
  cp -r "$ROOT/config" "$NATIVE_DIR/$role/config"
  # beckn-onix's plugin manager walks pluginManager.root with
  # filepath.WalkDir, which Lstats the root itself - a symlinked root is
  # seen as a non-directory and never descended into, silently yielding an
  # empty plugin set ("plugin cache not found" etc). Copy instead.
  if [ ! -d "$NATIVE_DIR/$role/plugins" ]; then
    cp -r "$ONIX_SRC/plugins" "$NATIVE_DIR/$role/plugins"
  fi

  sed -i 's#redis:6379#127.0.0.1:6379#' "$NATIVE_DIR/$role/config/$role.yaml"
  sed -i 's#http://onix-bap:8081/#http://127.0.0.1:8081/#' "$NATIVE_DIR/$role/config/routing/"*.yaml
  sed -i 's#http://onix-bpp:8082/#http://127.0.0.1:8082/#' "$NATIVE_DIR/$role/config/routing/"*.yaml
  sed -i 's#http://sandbox-bap:3001/#http://127.0.0.1:3001/#' "$NATIVE_DIR/$role/config/routing/"*.yaml
  sed -i 's#http://sandbox-bpp:3002/#http://127.0.0.1:3002/#' "$NATIVE_DIR/$role/config/routing/"*.yaml
done

# --- 3. Redis ----------------------------------------------------------
if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
  echo "Starting redis-server on :6379..."
  redis-server --daemonize yes --port 6379 --logfile "$NATIVE_DIR/logs/redis.log"
  sleep 1
fi

# --- 4. Sandbox stubs ----------------------------------------------------
cat > "$NATIVE_DIR/sandbox_stub.py" <<'PYEOF'
import http.server, sys, json

port = int(sys.argv[1])
name = sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        print(f"=== [{name}] {self.path} ===", flush=True)
        try:
            print(json.dumps(json.loads(body), indent=2), flush=True)
        except Exception:
            print(body.decode("utf-8", errors="replace"), flush=True)
        print("=== end ===", flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ACK"}')

    def log_message(self, fmt, *args):
        pass

http.server.HTTPServer(("0.0.0.0", port), Handler).serve_forever()
PYEOF

pidfile="$NATIVE_DIR/pids"
: > "$pidfile"

start_bg() {
  local name="$1"; shift
  nohup "$@" > "$NATIVE_DIR/logs/${name}.log" 2>&1 &
  echo "$! ${name}" >> "$pidfile"
  echo "  started $name (pid $!) -> $NATIVE_DIR/logs/${name}.log"
}

echo "Starting sandbox stubs..."
start_bg sandbox-bap python3 "$NATIVE_DIR/sandbox_stub.py" 3001 sandbox-bap
start_bg sandbox-bpp python3 "$NATIVE_DIR/sandbox_stub.py" 3002 sandbox-bpp

echo "Starting onix-bap (:8081) and onix-bpp (:8082)..."
(cd "$NATIVE_DIR/bap" && start_bg onix-bap "$NATIVE_DIR/onix-server" --config=config/bap.yaml)
(cd "$NATIVE_DIR/bpp" && start_bg onix-bpp "$NATIVE_DIR/onix-server" --config=config/bpp.yaml)

sleep 2

cat <<EOF

Endpoints:
  BAP caller   http://localhost:8081/bap/caller/<action>
  BAP receiver http://localhost:8081/bap/receiver/<on_action>
  BPP receiver http://localhost:8082/bpp/receiver/<action>
  BPP caller   http://localhost:8082/bpp/caller/<on_action>

Try it:
  scripts/send-payload.sh bap-caller:discover payloads/agri-schemes/search.json

Watch it happen:
  tail -f .native/logs/onix-bap.log .native/logs/onix-bpp.log

Stop everything:
  scripts/native-stop.sh
EOF
