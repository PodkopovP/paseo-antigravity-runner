#!/usr/bin/env bash
set -u

# ============================================================================
# Antigravity Remote (self-hosted) — container entrypoint
# ============================================================================
# Runs the Antigravity 2.0 hub language server headless in standalone "hub"
# mode. That single process serves the full Antigravity web UI *and* the agent
# backend on one local HTTP port. A host-rewriting reverse proxy (proxy.js)
# fronts it so a Cloudflare Tunnel can reach it, and cloudflared publishes it.
#
#   phone/browser --HTTPS--> Cloudflare edge (Access + WARP)
#                 --tunnel--> cloudflared --> proxy.js :8765
#                 --rewrite Host/Origin--> language_server hub :HUB_HTTP_PORT
# ============================================================================

HUB_HTTP_PORT="${HUB_HTTP_PORT:-8090}"
PROXY_LISTEN_PORT="${PROXY_LISTEN_PORT:-8765}"
AGY_IDE_VERSION="${AGY_IDE_VERSION:-2.8.1}"
AGY_HOSTNAME="${AGY_HOSTNAME:-$(hostname)}"
API_SERVER_URL="${AGY_API_SERVER_URL:-https://generativelanguage.googleapis.com}"
CLOUD_CODE_ENDPOINT="${AGY_CLOUD_CODE_ENDPOINT:-https://daily-cloudcode-pa.googleapis.com}"
HUB_LOG="/tmp/language_server.log"

# --- Antigravity credentials ------------------------------------------------
# Inject every known credential file so whichever one the standalone hub reads
# is present. Export these from a logged-in machine with
# scripts/export-credentials.sh.

mkdir -p /root/.gemini /root/.gemini/antigravity-cli

if [ -n "${OAUTH_CREDS_JSON:-}" ]; then
  printf '%s' "$OAUTH_CREDS_JSON" > /root/.gemini/oauth_creds.json
  echo "Injected oauth_creds.json."
fi

if [ -n "${JETSKI_STANDALONE_OAUTH_TOKEN_B64:-}" ]; then
  printf '%s' "$JETSKI_STANDALONE_OAUTH_TOKEN_B64" | base64 -d \
    > /root/.gemini/jetski-standalone-oauth-token
  chmod 600 /root/.gemini/jetski-standalone-oauth-token
  echo "Injected jetski-standalone-oauth-token."
fi

if [ -n "${AGY_OAUTH_TOKEN_B64:-}" ]; then
  printf '%s' "$AGY_OAUTH_TOKEN_B64" | base64 -d \
    > /root/.gemini/antigravity-cli/antigravity-oauth-token
  chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token
  echo "Injected antigravity-cli oauth token."
fi

if [ -n "${GOOGLE_ACCOUNTS_JSON:-}" ]; then
  printf '%s' "$GOOGLE_ACCOUNTS_JSON" > /root/.gemini/google_accounts.json
  echo "Injected google_accounts.json."
fi

# --- Enable the built-in remote-control feature -----------------------------
# Merge remote-control settings into ~/.gemini/config/config.json without
# clobbering anything already there.

node - "$AGY_HOSTNAME" <<'JS'
const fs = require("fs");
const path = "/root/.gemini/config/config.json";
const hostname = process.argv[2] || "workstation";
fs.mkdirSync("/root/.gemini/config", { recursive: true });
let config = {};
try { config = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
config.userSettings ??= {};
config.userSettings.remoteControlEnabled = true;
config.userSettings.remoteControlHostname = hostname;
config.userSettings.cliRemoteControlHostname = hostname;
fs.writeFileSync(path, JSON.stringify(config, null, 2));
console.log(`Remote control enabled in config.json (hostname="${hostname}").`);
JS

# --- Seed onboarding-complete state ------------------------------------------
# On a fresh app data dir the hub serves the desktop onboarding wizard, whose
# final sign-in step only completes inside the desktop shell — in a plain
# browser it hangs on "Success, Continuing...". Mark onboarding complete
# before the hub starts. Appending to a text proto merges fields, so this is
# safe on an existing state file; the grep guard keeps it one-shot.

STATE_FILE=/root/.gemini/antigravity/antigravity_state.pbtxt
mkdir -p /root/.gemini/antigravity
if ! grep -q "AGENT_ONBOARDING_STATE_COMPLETED" "$STATE_FILE" 2>/dev/null; then
  cat >> "$STATE_FILE" <<'EOF'
post_onboarding: {
  completed_steps: POST_ONBOARDING_STEP_TYPE_MANAGER_WELCOME
  completed_steps: POST_ONBOARDING_STEP_TYPE_USAGE_MODE
  completed_steps: POST_ONBOARDING_STEP_TYPE_AGENT_CONFIGURATION
  completed_steps: POST_ONBOARDING_STEP_TYPE_ADD_WORKSPACE
}
agent_onboarding_completed: AGENT_ONBOARDING_STATE_COMPLETED
EOF
  echo "Seeded onboarding-complete state (skips the desktop-only wizard)."
fi

# --- Git / GitHub -----------------------------------------------------------

if [ -n "${GIT_USER_NAME:-}" ]; then git config --global user.name "$GIT_USER_NAME"; fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git || echo "WARNING: 'gh auth setup-git' failed; continuing."
fi

# --- Locate the hub language server -----------------------------------------

LS_BIN="${LANGUAGE_SERVER_BIN:-$(command -v language_server || true)}"
if [ -z "$LS_BIN" ] || [ ! -x "$LS_BIN" ]; then
  echo "FATAL: language_server binary not found. Set LANGUAGE_SERVER_BIN or"
  echo "       bake it into the image (see Dockerfile ANTIGRAVITY_HUB_URL)." >&2
  exit 1
fi

CSRF_TOKEN="$(cat /proc/sys/kernel/random/uuid)"

# --- Launch the hub language server -----------------------------------------
# One process serves the web UI and the agent backend on HUB_HTTP_PORT. The
# CSRF token is embedded into the served HTML automatically, so the browser
# picks it up on load — nothing to enter by hand.

echo "Starting Antigravity hub language server on 127.0.0.1:${HUB_HTTP_PORT} ..."
"$LS_BIN" \
  --standalone \
  --override_ide_name antigravity \
  --subclient_type hub \
  --override_ide_version "$AGY_IDE_VERSION" \
  --override_user_agent_name antigravity \
  --http_server_port "$HUB_HTTP_PORT" \
  --https_server_port 0 \
  --csrf_token "$CSRF_TOKEN" \
  --app_data_dir antigravity \
  --api_server_url "$API_SERVER_URL" \
  --cloud_code_endpoint "$CLOUD_CODE_ENDPOINT" \
  --enable_sidecars \
  > "$HUB_LOG" 2>&1 &
HUB_PID=$!

# Wait for the HTTP port to answer.
hub_ready=false
for _ in $(seq 1 60); do
  if ! kill -0 "$HUB_PID" 2>/dev/null; then
    echo "FATAL: language server exited during startup. Last log lines:" >&2
    tail -n 30 "$HUB_LOG" >&2
    exit 1
  fi
  if timeout 2 bash -c "</dev/tcp/127.0.0.1/${HUB_HTTP_PORT}" 2>/dev/null; then
    hub_ready=true
    break
  fi
  sleep 1
done

if [ "$hub_ready" != true ]; then
  echo "FATAL: hub HTTP port ${HUB_HTTP_PORT} never came up. Last log lines:" >&2
  tail -n 30 "$HUB_LOG" >&2
  exit 1
fi
echo "Hub is up. (auth: check $HUB_LOG for 'not logged into Antigravity' if the UI is empty)"

# --- Launch the host-rewriting reverse proxy --------------------------------

echo "Starting host-rewrite proxy on 0.0.0.0:${PROXY_LISTEN_PORT} ..."
HUB_HTTP_PORT="$HUB_HTTP_PORT" PROXY_LISTEN_PORT="$PROXY_LISTEN_PORT" \
  node /app/proxy.js &
PROXY_PID=$!

# --- Launch cloudflared (optional) ------------------------------------------
# With a tunnel token the container publishes itself to Cloudflare. Point the
# tunnel's public hostname at http://localhost:${PROXY_LISTEN_PORT} in the
# Cloudflare Zero Trust dashboard, and gate it with Access + WARP.

CLOUDFLARED_PID=""
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "Starting cloudflared tunnel ..."
  cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" &
  CLOUDFLARED_PID=$!
else
  echo "CLOUDFLARE_TUNNEL_TOKEN not set — skipping cloudflared."
  echo "The proxy is reachable on host port ${PROXY_LISTEN_PORT}; run your own tunnel/VPN."
fi

# --- Supervise: if any critical child dies, tear the container down ---------

term() {
  echo "Shutting down ..."
  kill "$HUB_PID" "$PROXY_PID" ${CLOUDFLARED_PID:+$CLOUDFLARED_PID} 2>/dev/null
  wait 2>/dev/null
  exit 0
}
trap term TERM INT

while true; do
  kill -0 "$HUB_PID" 2>/dev/null    || { echo "language server died"; term; }
  kill -0 "$PROXY_PID" 2>/dev/null  || { echo "proxy died"; term; }
  if [ -n "$CLOUDFLARED_PID" ] && ! kill -0 "$CLOUDFLARED_PID" 2>/dev/null; then
    echo "cloudflared died"; term
  fi
  sleep 5
done
