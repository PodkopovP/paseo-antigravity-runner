# Antigravity & Claude Remote Control — self-hosted combo

Run the official **Antigravity Remote Control daemon** and **Claude Code Remote Control daemon**
headless on your own server in Docker, and drive them from your phone or any browser via Google's
hosted [Remote Control dashboard](https://antigravity.google.com) and Anthropic's
[Claude web/mobile interface](https://claude.ai/code) — **outbound connections only**: no open ports,
no tunnels, no reverse proxies.

Both agents share the **same `/root/dev` workspace volume**, allowing you to combo both agents
on the exact same code repositories and projects seamlessly.

```
┌──────────────┐   HTTPS   ┌ antigravity.google.com ┐   outbound   ┌── your server (Docker) ──────────────┐
│ phone/browser│ ────────► │ Antigravity Dashboard  │ ◄─────────── │ agy --remote-control                 │
└──────────────┘           └────────────────────────┘              │   (service: antigravity-remote)      │
                                                                   │                  │                   │
                                                                   │                  ▼                   │
                                                                   │         /root/dev (shared volume)    │
                                                                   │                  ▲                   │
┌──────────────┐   HTTPS   ┌ claude.ai / mobile     ┐   outbound   │                  │                   │
│ phone/browser│ ────────► │ Claude Code Interface  │ ◄─────────── │ claude --remote-control              │
└──────────────┘           └────────────────────────┘              │   (service: claude-remote)           │
                                                                   └──────────────────────────────────────┘
```

---

## ⚡ Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
```

The script checks prerequisites, creates `.env`, builds the unified image, walks you through
the one-time sign-ins for Antigravity and Claude Code if needed, and starts the containers.

- Drive Antigravity: open <https://antigravity.google.com> with your Google Account.
- Drive Claude Code: open <https://claude.ai/code> or the Claude mobile app.

---

## 🛠 Manual setup

```bash
git clone https://github.com/PodkopovP/paseo-antigravity-runner.git
cd paseo-antigravity-runner
cp .env.example .env          # everything in it is optional
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
   *(Alternatively, set `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` in `.env`)*

### Launch:

```bash
docker compose up -d          # start both daemons
```

Or start either daemon individually:
```bash
docker compose up -d antigravity-remote   # only Antigravity
docker compose up -d claude-remote        # only Claude Code
```

Auth tokens live in the `gemini-home` and `claude-home` Docker volumes, so sign-in is one-time;
both daemons refresh their credentials automatically from then on.

---

## 🔄 Updating

The Antigravity CLI and Claude Code CLI self-update or can be updated on restart:

```bash
docker compose restart        # restart daemons & apply pending updates
./setup.sh                    # update this repo, rebuild, restart
```

---

## ⚙️ Configuration reference

All optional, set in `.env`:

| Variable | Purpose |
| --- | --- |
| `AGY_HOSTNAME` | Antigravity instance name shown in the dashboard (default: saved name, or auto-generated) |
| `AGY_HUB_PORT` | Local hub web UI port inside the Antigravity container (default: 4400) |
| `CLAUDE_NAME` | Claude Code session name (default: `${AGY_HOSTNAME}-claude` or `remote-claude`) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Optional pre-generated OAuth token from `claude setup-token` |
| `ANTHROPIC_API_KEY` | Optional Anthropic API key |
| `CLAUDE_EXTRA_ARGS` | Extra flags passed to Claude Code (e.g. `--dangerously-skip-permissions`) |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | Git identity inside workspaces (used by both agents) |
| `GITHUB_TOKEN` | Lets both agents clone private repos, push, and open PRs |

---

## 🧩 How it works

- **Unified Docker image**: Installs both `agy` (Antigravity CLI) and `claude` (Claude Code CLI) along with `gh` (GitHub CLI), `git`, `zstd`, `jq`, and `tini`.
- **Shared Workspaces**: Both containers mount the same named volume `workspaces:/root/dev`. Code generated or edited by Antigravity is immediately available to Claude, and vice versa.
- **`agy --remote-control`**: Registers with Google's Remote Control service over an outbound connection. You interact with it from <https://antigravity.google.com>.
- **`claude --remote-control`**: Registers with Anthropic's Remote Control service over an outbound connection. You interact with it from <https://claude.ai/code> or the Claude mobile app.
- **`entrypoint.sh`**: Handles git configuration, seeds onboarding/trust state to prevent headless interactive hangs, runs interactive sign-in workflows, and starts the daemons cleanly under `tini`.
- **Combo mode in a single container**: If you prefer running both daemons in one single container instead of separate Docker Compose services, run `/entrypoint.sh combo`.
