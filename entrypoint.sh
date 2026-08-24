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

mkdir -p /root/.gemini

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
  echo "Sign in interactively:  docker compose run --rm antigravity-remote"
  echo "Starting anyway — watch these logs for a sign-in URL and paste-code prompt,"
  echo "or open a shell in the container and run:  agy --remote-control --hub-port 4499"
fi

echo "Starting Antigravity remote-control daemon ..."
exec agy "${args[@]}"
