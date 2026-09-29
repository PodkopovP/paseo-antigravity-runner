#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Antigravity & Claude Remote Control (self-hosted) — container entrypoint
# ============================================================================
# Supports running:
#   - antigravity (default): agy --remote-control
#   - claude: claude --remote-control
#   - combo: runs both daemons concurrently in the same container
#   - arbitrary commands: executes given command line
# ============================================================================

MODE="${1:-antigravity}"

export PATH="/root/.local/bin:${PATH}"

# --- Common directories & Git / GitHub Setup ---------------------------------
mkdir -p /root/dev /root/.gemini /root/.claude

if [ -n "${GIT_USER_NAME:-}" ]; then git config --global user.name "$GIT_USER_NAME" || true; fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then git config --global user.email "$GIT_USER_EMAIL" || true; fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git || echo "WARNING: 'gh auth setup-git' failed; continuing."
fi

# ============================================================================
# Function: Run Antigravity Remote Control
# ============================================================================
run_antigravity() {
  TOKEN_FILE=/root/.gemini/jetski-standalone-oauth-token

  # Mirrors ExecStartPre in the official daemon's systemd unit; the CLI also
  # self-updates in the background while running.
  agy --bg-updater || true

  agy_args=(--remote-control --hub-port "${AGY_HUB_PORT:-4400}")
  if [ -n "${AGY_HOSTNAME:-}" ]; then
    agy_args+=(--remote-control-name "$AGY_HOSTNAME")
  fi

  if [ ! -s "$TOKEN_FILE" ]; then
    if [ -t 0 ]; then
      echo "--------------------------------------------------------------"
      echo "First-time sign-in for Antigravity."
      echo "Open the URL printed below and paste the code back if prompted."
      echo "This exits automatically once signed in."
      echo "--------------------------------------------------------------"
      ( while [ ! -s "$TOKEN_FILE" ]; do sleep 2; done; sleep 2
        pkill -P $$ -f -- "--remote-control" 2>/dev/null ) &
      wd=$!
      trap 'echo' INT
      agy "${agy_args[@]}" || true
      trap - INT
      kill "$wd" 2>/dev/null || true
      wait "$wd" 2>/dev/null || true
      if [ -s "$TOKEN_FILE" ]; then
        echo "✓ Signed in to Antigravity. Start the daemon with: docker compose up -d"
        exit 0
      fi
      echo "Sign-in did not complete; no token at $TOKEN_FILE." >&2
      exit 1
    fi
    echo "WARNING: Antigravity not signed in ($TOKEN_FILE missing)."
    echo "Sign in interactively:  docker compose run --rm antigravity-remote"
    echo "Starting anyway — watch these logs for a sign-in URL."
  fi

  echo "Starting Antigravity remote-control daemon ..."
  if [ "${RUN_BG:-false}" = "true" ]; then
    agy "${agy_args[@]}" &
    AGY_PID=$!
  else
    exec agy "${agy_args[@]}"
  fi
}

# ============================================================================
# Function: Run Claude Remote Control
# ============================================================================
run_claude() {
  export CLAUDE_CONFIG_DIR=/root/.claude
  cd /root/dev

  # Seed onboarding & workspace trust into .claude.json so Claude doesn't block
  # on the interactive theme picker or workspace safety prompt in headless mode.
  CONFIG_FILE="/root/.claude/.claude.json"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat << 'EOF' > "$CONFIG_FILE"
{
  "installMethod": "native",
  "autoUpdates": false,
  "hasCompletedOnboarding": true,
  "theme": "dark",
  "hasSeenAutoDefaultNotice": true,
  "projects": {
    "/root/dev": {
      "hasTrustDialogAccepted": true
    }
  }
}
EOF
  else
    python3 -c '
import json, os
p = "/root/.claude/.claude.json"
if os.path.exists(p):
    try:
        with open(p, "r") as f: d = json.load(f)
        d.setdefault("hasCompletedOnboarding", True)
        d.setdefault("theme", "dark")
        d.setdefault("hasSeenAutoDefaultNotice", True)
        d.setdefault("projects", {}).setdefault("/root/dev", {})["hasTrustDialogAccepted"] = True
        with open(p, "w") as f: json.dump(d, f, indent=2)
    except Exception: pass
' 2>/dev/null || true
  fi

  claude_name="${CLAUDE_NAME:-${AGY_HOSTNAME:-remote-claude}}"
  claude_args=(--remote-control "$claude_name")
  if [ -n "${CLAUDE_EXTRA_ARGS:-}" ]; then
    read -r -a extra_arr <<< "$CLAUDE_EXTRA_ARGS"
    claude_args+=("${extra_arr[@]}")
  fi

  # Check if signed in via credentials file, env var, or API key
  IS_LOGGED_IN=false
  if [ -s /root/.claude/.credentials.json ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    IS_LOGGED_IN=true
  elif claude auth status >/dev/null 2>&1; then
    IS_LOGGED_IN=true
  fi

  if [ "$IS_LOGGED_IN" = "false" ]; then
    if [ -t 0 ]; then
      echo "--------------------------------------------------------------"
      echo "First-time sign-in for Claude Code."
      echo "Follow the link below to sign in with your Claude account."
      echo "--------------------------------------------------------------"
      claude auth login || true
      if claude auth status >/dev/null 2>&1 || [ -s /root/.claude/.credentials.json ]; then
        echo "✓ Signed in to Claude. Start the daemon with: docker compose up -d"
        exit 0
      fi
      echo "Sign-in did not complete." >&2
      exit 1
    fi
    echo "WARNING: Claude is not signed in."
    echo "Sign in interactively:  docker compose run --rm claude-remote"
    echo "Or set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in .env"
    echo "Starting anyway — watch logs for prompts."
  fi

  echo "Starting Claude remote-control daemon in /root/dev (session: $claude_name) ..."
  if [ "${RUN_BG:-false}" = "true" ]; then
    claude "${claude_args[@]}" &
    CLAUDE_PID=$!
  else
    exec claude "${claude_args[@]}"
  fi
}

# --- Execution dispatch -----------------------------------------------------
case "$MODE" in
  antigravity)
    run_antigravity
    ;;
  claude)
    run_claude
    ;;
  combo|both)
    RUN_BG=true
    run_antigravity
    run_claude
    echo "Running both Antigravity and Claude Remote Control daemons..."
    trap 'kill -TERM $AGY_PID $CLAUDE_PID 2>/dev/null; exit 0' TERM INT
    wait -n "$AGY_PID" "$CLAUDE_PID" || true
    ;;
  *)
    exec "$@"
    ;;
esac
