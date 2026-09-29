#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Antigravity & Claude Remote Control (self-hosted) — container entrypoint
# ============================================================================
# Supports running:
#   - combo (default): runs both daemons concurrently in the same container
#   - antigravity: agy --remote-control
#   - claude: claude --remote-control
#   - arbitrary commands: executes given command line
# ============================================================================

MODE="${1:-combo}"

export PATH="/root/.gemini/antigravity-cli/bin:/root/.gemini/node/bin:/root/.local/bin:${PATH}"
export IS_SANDBOX="${IS_SANDBOX:-1}"
export CLAUDE_CONFIG_DIR=/root/.claude

# --- Workspace Directory Setup ----------------------------------------------
# Supports /workspace (Coolify volume) or /root/dev (Docker Compose default).
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
if [ ! -d "$WORKSPACE_DIR" ] && [ -d "/root/dev" ]; then
  WORKSPACE_DIR="/root/dev"
fi
mkdir -p "$WORKSPACE_DIR" /root/.gemini /root/.claude

# Create convenience symlink between /workspace and /root/dev if not existing
if [ "$WORKSPACE_DIR" = "/workspace" ] && [ ! -e /root/dev ]; then
  ln -sf /workspace /root/dev 2>/dev/null || true
elif [ "$WORKSPACE_DIR" = "/root/dev" ] && [ ! -e /workspace ]; then
  ln -sf /root/dev /workspace 2>/dev/null || true
fi
cd "$WORKSPACE_DIR"

# --- Git / GitHub Setup -----------------------------------------------------
if [ -n "${GIT_USER_NAME:-}" ]; then git config --global user.name "$GIT_USER_NAME" 2>/dev/null || true; fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then git config --global user.email "$GIT_USER_EMAIL" 2>/dev/null || true; fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
  gh auth setup-git 2>/dev/null || echo "WARNING: 'gh auth setup-git' failed; continuing."
fi

# --- Sync MCP Servers & Trust Configuration into Claude ---------------------
# Claude and Antigravity share the same MCP servers and workspace trust.
python3 -c '
import json, os

workspace_dir = os.environ.get("WORKSPACE_DIR", "/workspace")
gemini_mcp = "/root/.gemini/config/mcp_config.json"
claude_dir = "/root/.claude"
claude_cfg = os.path.join(claude_dir, ".claude.json")

os.makedirs(claude_dir, exist_ok=True)

cd = {}
if os.path.exists(claude_cfg):
    try:
        with open(claude_cfg, "r") as f:
            cd = json.load(f)
    except Exception:
        pass

# Ensure basic onboarding & workspace trust settings
cd.setdefault("installMethod", "native")
cd.setdefault("autoUpdates", False)
cd.setdefault("hasCompletedOnboarding", True)
cd.setdefault("theme", "dark")
cd.setdefault("hasSeenAutoDefaultNotice", True)

projects = cd.setdefault("projects", {})
projects.setdefault("/root/dev", {})["hasTrustDialogAccepted"] = True
projects.setdefault("/workspace", {})["hasTrustDialogAccepted"] = True
projects.setdefault(workspace_dir, {})["hasTrustDialogAccepted"] = True

# Sync MCP servers from Antigravity to Claude Code
if os.path.exists(gemini_mcp):
    try:
        with open(gemini_mcp, "r") as f:
            gm = json.load(f)
        servers = gm.get("mcpServers", {})
        cd_servers = cd.setdefault("mcpServers", {})
        synced = 0
        for name, cfg in servers.items():
            if "serverUrl" in cfg and "type" not in cfg:
                cd_servers[name] = {"type": "http", "url": cfg["serverUrl"]}
                synced += 1
            elif "command" in cfg:
                cd_servers[name] = {
                    "command": cfg["command"],
                    "args": cfg.get("args", []),
                    "env": cfg.get("env", {})
                }
                synced += 1
        if synced > 0:
            print(f"✓ Synced {synced} MCP server(s) from Antigravity to Claude Code.")
    except Exception as e:
        print(f"Notice: MCP sync warning: {e}")

try:
    with open(claude_cfg, "w") as f:
        json.dump(cd, f, indent=2)
except Exception as e:
    print(f"Notice: Could not write Claude config: {e}")
' 2>/dev/null || true

# ============================================================================
# Function: Run Antigravity Remote Control
# ============================================================================
run_antigravity() {
  TOKEN_FILE=/root/.gemini/jetski-standalone-oauth-token
  cd "$WORKSPACE_DIR"

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
        echo "✓ Signed in to Antigravity."
        if [ "$MODE" = "antigravity" ]; then
          exit 0
        fi
      else
        echo "Sign-in did not complete; no token at $TOKEN_FILE." >&2
        if [ "$MODE" = "antigravity" ]; then
          exit 1
        fi
      fi
    else
      echo "WARNING: Antigravity not signed in ($TOKEN_FILE missing)."
      echo "Sign in interactively:  docker compose run --rm antigravity-remote"
      echo "Starting anyway — watch these logs for a sign-in URL."
    fi
  fi

  echo "Starting Antigravity remote-control daemon in $WORKSPACE_DIR ..."
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
  cd "$WORKSPACE_DIR"

  claude_name="${CLAUDE_NAME:-${AGY_HOSTNAME:-remote-claude}}"
  claude_args=(--remote-control "$claude_name")
  if [ -n "${CLAUDE_EXTRA_ARGS:-}" ]; then
    read -r -a extra_arr <<< "$CLAUDE_EXTRA_ARGS"
    claude_args+=("${extra_arr[@]}")
  fi

  # Check if signed in via credentials file, env var, or cached session
  IS_LOGGED_IN=false
  if [ -s /root/.claude/.credentials.json ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
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
        echo "✓ Signed in to Claude."
        if [ "$MODE" = "claude" ]; then
          exit 0
        fi
      else
        echo "Sign-in did not complete." >&2
        if [ "$MODE" = "claude" ]; then
          exit 1
        fi
      fi
    else
      echo "WARNING: Claude is not signed in."
      echo "Attach to the container to sign in: docker exec -it <container> tmux attach -t claude"
      echo "Or generate a token locally ('claude setup-token') and set CLAUDE_CODE_OAUTH_TOKEN in Coolify / .env"
      echo "Starting anyway — watch logs or attach to tmux session for prompts."
    fi
  fi

  echo "Starting Claude remote-control daemon in $WORKSPACE_DIR (session: $claude_name) ..."
  if [ "${RUN_BG:-false}" = "true" ]; then
    # Start inside a detached tmux session to provide a persistent PTY so Claude Code
    # runs cleanly in headless environments without TTY crashes, and allows attaching via
    # `docker exec -it <container> tmux attach -t claude`.
    tmux kill-session -t claude 2>/dev/null || true
    tmux new-session -d -s claude -c "$WORKSPACE_DIR" "claude ${claude_args[*]}"
    # Monitor the tmux session
    ( while tmux has-session -t claude 2>/dev/null; do sleep 3; done ) &
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
    echo "Running both Antigravity and Claude Remote Control daemons in $WORKSPACE_DIR..."
    trap 'kill -TERM $AGY_PID 2>/dev/null; tmux kill-session -t claude 2>/dev/null; kill -TERM $CLAUDE_PID 2>/dev/null; exit 0' TERM INT
    wait -n "$AGY_PID" "$CLAUDE_PID" || true
    ;;
  *)
    exec "$@"
    ;;
esac
