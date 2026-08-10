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

# --- Configure Paseo agent providers ------------------------
# antigravity: agy-agent-acp keeps a warm agy language server per workspace
#   (~1.3s/turn via its local Connect API). Set AGY_ACP_TRANSPORT=cli to
#   force the slower spawn-per-turn fallback.
# gemini: persistent ACP agent, but only serves paid API keys since
#   2026-06-18 — enabled only when GEMINI_API_KEY is set. Set
#   GEMINI_PROVIDER_ENABLED=false to force it off.

node - <<'JS'
const fs = require("fs");
const path = "/root/.paseo/config.json";
let config = { version: 1 };
try { config = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
config.agents ??= {};
config.agents.providers ??= {};

// Drop any provider left over from the old paseo_agy bridge (agy-acp binary).
for (const [key, provider] of Object.entries(config.agents.providers)) {
  const command = Array.isArray(provider?.command) ? provider.command : [];
  if (command.some((arg) => typeof arg === "string" && arg.includes("agy-acp/"))) {
    delete config.agents.providers[key];
    console.log(`Removed legacy provider: ${key}`);
  }
}

config.agents.providers.antigravity = {
  extends: "acp",
  label: "Google Antigravity",
  description: "Antigravity via agy-agent-acp (warm language server)",
  command: ["agy-agent-acp"],
  env: { AGY_ACP_TRANSPORT: process.env.AGY_ACP_TRANSPORT || "connect" },
  enabled: true,
};

const geminiEnabled =
  Boolean(process.env.GEMINI_API_KEY) &&
  process.env.GEMINI_PROVIDER_ENABLED !== "false";
config.agents.providers.gemini = {
  extends: "acp",
  label: "Gemini CLI",
  description: "Google Gemini CLI (persistent ACP agent)",
  command: ["gemini", "--acp"],
  enabled: geminiEnabled,
};

fs.writeFileSync(path, JSON.stringify(config, null, 2));
console.log(
  `Providers configured: antigravity (agy-agent-acp), gemini (${geminiEnabled ? "enabled" : "disabled — no GEMINI_API_KEY"}).`
);
JS

# --- Sanity check: does 'agy models' respond? ---------------
# Validates that the injected credentials give agy a working session.
# If this hangs, the warm harness and the CLI fallback will both fail.

if command -v agy >/dev/null 2>&1; then
  if timeout 20s agy models >/dev/null 2>&1; then
    echo "'agy models' responded OK — Antigravity auth is working."
  else
    echo "WARNING: 'agy models' hung or failed. Check your injected credentials;"
    echo "         the Antigravity provider will not work until auth is fixed."
  fi
fi

# --- Start Paseo --------------------------------------------
# Remove stale daemon state left over from a previous container run.

rm -f /root/.paseo/paseo.pid /root/.paseo/daemon.sock

exec paseo start --foreground
