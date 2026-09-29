# Antigravity & Claude Remote Control — self-hosted combo

Run the official **Antigravity Remote Control daemon** and **Claude Code Remote Control daemon**
headless on your own server or in Coolify in Docker, and drive them from your phone or any browser via Google's
hosted [Remote Control dashboard](https://antigravity.google.com) and Anthropic's
[Claude web/mobile interface](https://claude.ai/code) — **outbound connections only**: no open ports,
no tunnels, no reverse proxies.

Both agents run in the **same container and share the same `/workspace` volume and MCP servers**, allowing you to combo both agents on the exact same code repositories and projects seamlessly.

```
┌──────────────┐   HTTPS   ┌ antigravity.google.com ┐   outbound   ┌── your server / Coolify (Docker) ────┐
│ phone/browser│ ────────► │ Antigravity Dashboard  │ ◄─────────── │ agy --remote-control                 │
└──────────────┘           └────────────────────────┘              │   (CLI daemon)                       │
                                                                   │                  │                   │
                                                                   │                  ▼                   │
                                                                   │         /workspace (shared volume)   │
                                                                   │                  ▲                   │
┌──────────────┐   HTTPS   ┌ claude.ai / mobile     ┐   outbound   │                  │                   │
│ phone/browser│ ────────► │ Claude Code Interface  │ ◄─────────── │ claude --remote-control (in tmux)    │
└──────────────┘           └────────────────────────┘              │   (CLI daemon)                       │
                                                                   └──────────────────────────────────────┘
```

---

## ⚡ Quick start (Docker Compose)

```bash
curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
```

The script checks prerequisites, creates `.env`, builds the unified image, walks you through
the one-time sign-ins for Antigravity and Claude Code if needed, and starts the container.

- Drive Antigravity: open <https://antigravity.google.com> with your Google Account.
- Drive Claude Code: open <https://claude.ai/code> or the Claude mobile app.

---

## ☁️ Coolify Deployment

When deploying to **Coolify**:
1. Connect this repository and set branch to `remote`.
2. **Build Pack**: Select `Dockerfile`. The image defaults to running both daemons in combo mode.
3. **Persistent Storages** (Coolify -> Configuration -> Storages):
   - `/root/.gemini` (Antigravity auth tokens, settings, MCP config)
   - `/root/.claude` (Claude auth tokens, settings, MCP config)
   - `/workspace` (Shared git repository workspace)
   - `/root/.ssh` (Optional SSH keys)
4. **Authentication**:
   - **Antigravity**: Sign in once interactively or seed `/root/.gemini`.
   - **Claude Code**: Generate a token on your local machine using `claude setup-token` and set it as `CLAUDE_CODE_OAUTH_TOKEN` in Coolify Environment Variables. Alternatively, run `docker exec -it <container> tmux attach -t claude` on the host to complete browser login.

---

## 🛠 Manual setup (Local / Server)

```bash
git clone https://github.com/PodkopovP/paseo-antigravity-runner.git
cd paseo-antigravity-runner
cp .env.example .env
docker compose build
```

### One-time interactive sign-ins:

1. **Antigravity sign-in** (prints a Google auth URL; paste the code back):
   ```bash
   docker compose run --rm antigravity-remote
   ```

2. **Claude Code sign-in** (prints a Claude auth URL; paste the code back):
   ```bash
   docker compose run --rm claude-remote
   ```
   *(Alternatively, set `CLAUDE_CODE_OAUTH_TOKEN` in `.env`)*

### Launch:

```bash
docker compose up -d          # starts the unified agent-runner container
```

Auth tokens live in the `gemini-home` and `claude-home` Docker volumes, so sign-in is one-time;
both daemons refresh their credentials automatically from then on.

---

## 🤝 Driving Each Other Inside the Container

Since both CLIs are installed and share the workspace filesystem:

- **From Antigravity**: You can prompt Antigravity to run Claude via shell:
  ```bash
  claude -p "Refactor the test suite" --dangerously-skip-permissions
  ```
- **From Claude Code**: You can prompt Claude to run Antigravity via shell:
  ```bash
  agy -p "Review this diff" --dangerously-skip-permissions
  ```
- Both agents automatically share configured **MCP servers** (GitHub, Coolify, Redis, BetterStack, Chrome DevTools).

---

## ⚙️ Configuration reference

All optional, set in `.env` or Coolify Environment Variables:

| Variable | Purpose |
| --- | --- |
| `WORKSPACE_DIR` | Workspace directory where agents work (default: `/workspace` or `/root/dev`) |
| `IS_SANDBOX` | Set to `1` so Claude allows `--dangerously-skip-permissions` as root |
| `AGY_HOSTNAME` | Antigravity instance name shown in the dashboard (default: saved name, or auto-generated) |
| `AGY_HUB_PORT` | Local hub web UI port inside the container (default: 4400) |
| `CLAUDE_NAME` | Claude Code session name (default: `${AGY_HOSTNAME}` or `remote-claude`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Long-lived OAuth token generated via `claude setup-token` |
| `CLAUDE_EXTRA_ARGS` | Extra flags passed to Claude Code |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | Git identity inside workspaces (used by both agents) |
| `GITHUB_TOKEN` | Lets both agents clone private repos, push, and open PRs |

---

## 🧩 How it works

- **Unified Docker image**: Installs both `agy` (Antigravity CLI) and `claude` (Claude Code CLI) along with `tmux`, `gh` (GitHub CLI), `git`, `zstd`, `jq`, and `tini`.
- **Shared Workspaces**: Mounts `/workspace`. Code generated or edited by Antigravity is immediately available to Claude, and vice versa.
- **Shared MCPs**: On startup, `entrypoint.sh` syncs configured MCP servers from `/root/.gemini/config/mcp_config.json` into `/root/.claude/.claude.json`.
- **Persistent PTY with tmux**: Claude Code Remote Control runs inside a detached `tmux` session, ensuring it never crashes from missing TTY in headless environments, and allowing inspection with `docker exec -it <container> tmux attach -t claude`.
- **`agy --remote-control`**: Connects outbound to Google's Remote Control service (<https://antigravity.google.com>).
- **`claude --remote-control`**: Connects outbound to Anthropic's Remote Control service (<https://claude.ai/code>).
