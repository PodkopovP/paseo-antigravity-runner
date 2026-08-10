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

# --- Enable the Gemini CLI provider in Paseo ----------------
# Gemini CLI runs as a persistent ACP agent — no per-prompt cold start,
# unlike the agy bridge. NOTE: since June 18, 2026 Gemini CLI no longer
# serves Google AI Pro/Ultra or free individual OAuth accounts, so the
# provider is only enabled when GEMINI_API_KEY is set (paid/free-tier
# API key from AI Studio, or a Code Assist Standard/Enterprise setup).
# Set GEMINI_PROVIDER_ENABLED=false to force it off.

node - <<'JS'
const fs = require("fs");
const path = "/root/.paseo/config.json";
let config = { version: 1 };
try { config = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
config.agents ??= {};
config.agents.providers ??= {};
const hasApiKey = Boolean(process.env.GEMINI_API_KEY);
const enabled = hasApiKey && process.env.GEMINI_PROVIDER_ENABLED !== "false";
config.agents.providers.gemini = {
  extends: "acp",
  label: "Gemini CLI",
  description: "Google Gemini CLI (persistent ACP agent)",
  command: ["gemini", "--acp"],
  enabled,
};
fs.writeFileSync(path, JSON.stringify(config, null, 2));
console.log(
  enabled
    ? "Gemini CLI provider enabled (GEMINI_API_KEY present)."
    : "Gemini CLI provider disabled (no GEMINI_API_KEY set)."
);
JS

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
