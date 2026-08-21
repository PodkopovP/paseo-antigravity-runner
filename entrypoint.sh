#!/usr/bin/env bash
set -u

# ============================================================================
# Antigravity Remote Control (self-hosted) — container entrypoint
# ============================================================================
# Runs the official Antigravity CLI remote-control daemon:
#
#   agy --remote-control
#
# The daemon connects *outbound* to Google's Remote Control service; you drive
# it from https://antigravity.google.com with your Google account. No inbound
# ports, no tunnel, no proxy.
# ============================================================================

TOKEN_FILE=/root/.gemini/jetski-standalone-oauth-token

mkdir -p /root/.gemini /root/.gemini/antigravity-cli

# --- Seed credentials (optional) ---------------------------------------------
# Exported from a logged-in machine with scripts/export-credentials.sh. Each
# file is only seeded when missing, so tokens the daemon refreshes in the
# volume are never clobbered by stale .env values on restart. The daemon
# itself only needs $TOKEN_FILE; the others keep the CLI's other entry points
# signed in too.

if [ -n "${OAUTH_CREDS_JSON:-}" ] && [ ! -s /root/.gemini/oauth_creds.json ]; then
  printf '%s' "$OAUTH_CREDS_JSON" > /root/.gemini/oauth_creds.json
  echo "Seeded oauth_creds.json."
fi

if [ -n "${GOOGLE_ACCOUNTS_JSON:-}" ] && [ ! -s /root/.gemini/google_accounts.json ]; then
  printf '%s' "$GOOGLE_ACCOUNTS_JSON" > /root/.gemini/google_accounts.json
  echo "Seeded google_accounts.json."
fi

if [ -n "${JETSKI_STANDALONE_OAUTH_TOKEN_B64:-}" ] && [ ! -s "$TOKEN_FILE" ]; then
  printf '%s' "$JETSKI_STANDALONE_OAUTH_TOKEN_B64" | base64 -d > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "Seeded jetski-standalone-oauth-token."
fi

if [ -n "${AGY_OAUTH_TOKEN_B64:-}" ] && [ ! -s /root/.gemini/antigravity-cli/antigravity-oauth-token ]; then
  printf '%s' "$AGY_OAUTH_TOKEN_B64" | base64 -d \
    > /root/.gemini/antigravity-cli/antigravity-oauth-token
  chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token
  echo "Seeded antigravity-cli oauth token."
fi

# --- Git / GitHub -----------------------------------------------------------

if [ -n "${GIT_USER_NAME:-}" ]; then git config --global user.name "$GIT_USER_NAME"; fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git || echo "WARNING: 'gh auth setup-git' failed; continuing."
fi

# --- Apply any downloaded CLI update before starting --------------------------
# Mirrors ExecStartPre in the official daemon's systemd unit; the CLI also
# self-updates in the background while running.

agy --bg-updater || true

# --- Daemon arguments ---------------------------------------------------------
# Without --remote-control-name the daemon keeps the instance name saved in
# ~/.gemini/config/config.json (userSettings.cliRemoteControlHostname), or
# generates one on first run.

args=(--remote-control)
if [ -n "${AGY_HOSTNAME:-}" ]; then
  args+=(--remote-control-name "$AGY_HOSTNAME")
fi

# --- First-time sign-in --------------------------------------------------------
# The headless daemon reuses $TOKEN_FILE. When it is missing and we have a
# terminal (docker compose run --rm antigravity-remote), run the interactive
# sign-in once — a watchdog stops the CLI as soon as the token lands, exactly
# like the official installer — then exit so `docker compose up -d` starts the
# daemon cleanly. Without a terminal, start anyway: the sign-in URL is printed
# to the container logs.

if [ ! -s "$TOKEN_FILE" ]; then
  if [ -t 0 ]; then
    echo "--------------------------------------------------------------"
    echo "First-time sign-in. Open the URL printed below and paste the"
    echo "code back if prompted. This exits automatically once signed in."
    echo "--------------------------------------------------------------"
    ( while [ ! -s "$TOKEN_FILE" ]; do sleep 2; done; sleep 2
      pkill -P $$ -f -- "--remote-control" 2>/dev/null ) &
    wd=$!
    trap 'echo' INT
    agy "${args[@]}" || true
    trap - INT
    kill "$wd" 2>/dev/null || true
    wait "$wd" 2>/dev/null || true
    if [ -s "$TOKEN_FILE" ]; then
      echo "✓ Signed in. Start the daemon with:  docker compose up -d"
      exit 0
    fi
    echo "Sign-in did not complete; no token at $TOKEN_FILE." >&2
    exit 1
  fi
  echo "WARNING: not signed in ($TOKEN_FILE missing)."
  echo "Either sign in interactively:  docker compose run --rm antigravity-remote"
  echo "or seed exported credentials:  ./scripts/export-credentials.sh >> .env"
  echo "Starting anyway — watch these logs for a sign-in URL."
fi

echo "Starting Antigravity remote-control daemon ..."
exec agy "${args[@]}"
