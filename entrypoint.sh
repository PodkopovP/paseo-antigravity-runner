#!/usr/bin/env bash
set -u

# ============================================================
# Paseo + Antigravity headless runner — container entrypoint
# ============================================================

# --- Antigravity CLI credentials ----------------------------

if [ -n "${OAUTH_CREDS_JSON:-}" ]; then
  mkdir -p /root/.gemini
  printf '%s' "$OAUTH_CREDS_JSON" > /root/.gemini/oauth_creds.json
  echo "Injected OAuth credentials for Antigravity CLI."
fi

if [ -n "${AGY_OAUTH_TOKEN_B64:-}" ]; then
  mkdir -p /root/.gemini/antigravity-cli
  printf '%s' "$AGY_OAUTH_TOKEN_B64" | base64 -d > /root/.gemini/antigravity-cli/antigravity-oauth-token
  chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token
  echo "Injected base64 OAuth token for Antigravity CLI."
fi

# --- Optional MCP config ------------------------------------

if [ -n "${MCP_CONFIG_B64:-}" ]; then
  mkdir -p /root/.gemini/config
  printf '%s' "$MCP_CONFIG_B64" | base64 -d > /root/.gemini/config/mcp_config.json
  echo "Injected MCP configuration."
fi

# --- Git / GitHub -------------------------------------------

if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi

if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git || echo "WARNING: 'gh auth setup-git' failed; continuing without it."
fi

# --- Sanity check: does 'agy models' respond? ---------------
# The agy-acp bridge runs 'agy models' in the background every time it
# starts. If that command hangs (e.g. bad/missing credentials), hung agy
# processes accumulate and eat CPU/RAM. Surface that early in the logs.

if command -v agy >/dev/null 2>&1; then
  if timeout 20s agy models >/dev/null 2>&1; then
    echo "'agy models' responded OK — bridge model discovery will work."
  else
    echo "WARNING: 'agy models' hung or failed. Each agent start will leave a"
    echo "         stuck background process. Check your injected credentials."
  fi
fi

# --- Start Paseo --------------------------------------------
# Remove stale daemon state left over from a previous container run.

rm -f /root/.paseo/paseo.pid /root/.paseo/daemon.sock

exec paseo start --foreground
