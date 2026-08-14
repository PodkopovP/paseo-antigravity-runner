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
# MCP_CONFIG_B64 is the single source of truth: when unset, remove any
# persisted config too — every warm agy harness spawns ALL configured MCP
# servers as long-lived children, and a stale file on the persistent volume
# would silently resurrect them (~100-400MB RAM each).

if [ -n "${MCP_CONFIG_B64:-}" ]; then
  mkdir -p /root/.gemini/config
  printf '%s' "$MCP_CONFIG_B64" | base64 -d > /root/.gemini/config/mcp_config.json
  echo "Injected MCP configuration."
elif [ -f /root/.gemini/config/mcp_config.json ]; then
  rm -f /root/.gemini/config/mcp_config.json
  echo "Removed stale MCP configuration (MCP_CONFIG_B64 not set)."
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

// Drop stale provider entries: old paseo_agy bridge entries (agy-acp binary)
// and the transient "antigravity" key from an earlier revision of this script.
for (const [key, provider] of Object.entries(config.agents.providers)) {
  const command = Array.isArray(provider?.command) ? provider.command : [];
  const isOldBridge = command.some((arg) => typeof arg === "string" && arg.includes("agy-acp/"));
  const isTransientKey = key === "antigravity" && command[0] === "agy-agent-acp";
  if (isOldBridge || isTransientKey) {
    delete config.agents.providers[key];
    console.log(`Removed stale provider entry: ${key}`);
  }
}

// Keep the provider ID the old bridge used ("antigravity-acp") so drafts and
// agents persisted by the mobile app keep resolving after the swap.
config.agents.providers["antigravity-acp"] = {
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
  `Providers configured: antigravity-acp (agy-agent-acp), gemini (${geminiEnabled ? "enabled" : "disabled — no GEMINI_API_KEY"}).`
);
JS

# --- Sanity check: does 'agy models' respond? ---------------
# Validates that the injected credentials give agy a working session.
# If this hangs, the warm harness and the CLI fallback will both fail.
#
# On success the output is persisted to ~/.gemini/agy-models.txt — the
# patched adapter builds Paseo's model dropdown from it, so the picker
# tracks whatever agy actually serves instead of a hardcoded list. Written
# via tmp+mv so a killed probe never leaves a truncated catalog; a stale
# file from a previous start is kept as a better-than-fallback catalog.
#
# Run it in its own process group: agy spawns every configured MCP server
# (from MCP_CONFIG_B64) as child processes, and a plain 'timeout' would kill
# agy but orphan those children, which then spin on a closed stdin at 100%
# CPU. Killing the group reaps the lot.

if command -v agy >/dev/null 2>&1; then
  mkdir -p /root/.gemini
  setsid bash -c 'agy models > /root/.gemini/agy-models.txt.tmp 2>/dev/null && mv /root/.gemini/agy-models.txt.tmp /root/.gemini/agy-models.txt' &
  check_pid=$!
  agy_ok=false
  for _ in $(seq 1 30); do
    if ! kill -0 "$check_pid" 2>/dev/null; then
      if wait "$check_pid"; then agy_ok=true; fi
      break
    fi
    sleep 1
  done
  kill -TERM -- "-$check_pid" 2>/dev/null || true
  sleep 1
  kill -KILL -- "-$check_pid" 2>/dev/null || true
  rm -f /root/.gemini/agy-models.txt.tmp

  if [ "$agy_ok" = true ]; then
    echo "'agy models' responded OK — Antigravity auth is working; model catalog refreshed."
  else
    echo "WARNING: 'agy models' hung or failed within 30s. Check your injected"
    echo "         credentials; the Antigravity provider will not work until"
    echo "         auth is fixed. Note that a large MCP config (MCP_CONFIG_B64)"
    echo "         also slows agy startup — consider trimming it."
  fi
fi

# --- Start Paseo --------------------------------------------
# Remove stale daemon state left over from a previous container run.

rm -f /root/.paseo/paseo.pid /root/.paseo/daemon.sock

# Run the daemon worker directly instead of `paseo start --foreground`.
# The normal chain (CLI wrapper -> Paseo Supervisor -> Paseo Daemon) keeps
# two extra Node processes resident (~325MB RSS combined) whose jobs — pid
# locking, crash restart, self-update — are covered by the container itself
# (single process tree, Docker restart policy, pinned image). The worker is
# IPC-tolerant: it skips supervisor messaging when no IPC channel exists.
# Set PASEO_USE_SUPERVISOR=true to restore the stock chain.

DAEMON_WORKER=/usr/lib/node_modules/@getpaseo/cli/node_modules/@getpaseo/server/dist/server/server/daemon-worker.js

echo "Paseo daemon starting."
echo "To pair a device, run:  docker exec -it <container> paseo-pair"

if [ "${PASEO_USE_SUPERVISOR:-false}" = "true" ] || [ ! -f "$DAEMON_WORKER" ]; then
  exec paseo start --foreground
fi

exec node "$DAEMON_WORKER"
