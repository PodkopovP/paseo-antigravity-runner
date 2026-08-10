# Antigravity on your phone — self-hosted Paseo runner

Google Antigravity has no remote mode: the `agy` CLI only runs interactively
or one-shot, on the machine it's installed on. This repo packages a headless,
self-hostable runner that puts Antigravity behind [Paseo](https://paseo.sh) —
so you can start, steer, and review coding agents from the Paseo mobile/web
app, against repos living on your own server.

```
┌──────────────┐   E2EE relay    ┌────────────────────── your server ──────────────────────┐
│  Paseo app   │ ◄─────────────► │  Paseo daemon ◄─ACP─► agy-agent-acp ◄─► warm agy        │
│ (phone/web)  │  (or LAN/VPN)   │                        (adapter)        language server │
└──────────────┘                 └──────────────────────────────────────────────────────────┘
```

**Why the adapter matters:** most Antigravity bridges spawn a fresh `agy`
process per prompt (~3-6s of cold start every turn). This runner uses
[agy-agent-acp](https://github.com/jameslunardi/agy-agent-acp), which keeps
one warm Antigravity language server per workspace and drives it over its
local API — **~1.3s per turn**, with real streaming and per-tool permission
prompts delivered to your phone.

## Prerequisites

- A Docker host (any small VPS or home server; 1 vCPU / 2GB RAM is plenty)
- An Antigravity login on your local machine (IDE or `agy` CLI) — any account
  tier that Antigravity itself accepts
- The Paseo app: [app.paseo.sh](https://app.paseo.sh) (web) or the mobile app

## Quick start

**1. Clone and configure**

```bash
git clone <this-repo> && cd <this-repo>
cp .env.example .env
```

**2. Export your Antigravity credentials** — on the machine where you're
logged in to Antigravity:

```bash
./scripts/export-credentials.sh >> .env
```

(Or copy the values over manually — see `.env.example`. Treat them as
secrets; they grant access to your Antigravity account.)

**3. Build and start**

```bash
docker compose up -d --build
```

**4. Pair your phone**

```bash
docker compose exec paseo paseo onboard
```

Scan the QR code (or open the pairing link) with the Paseo app. Pairing is
end-to-end encrypted; the relay never sees your traffic in plaintext, and no
inbound ports need to be opened on your server.

**5. Add a repository**

```bash
docker compose exec paseo bash
cd /root/dev && git clone https://github.com/you/your-repo
```

(Set `GITHUB_TOKEN` in `.env` for private repos.) Then open the Paseo app,
pick the workspace, choose the **Google Antigravity** provider, and go.

## Permission modes

The adapter deliberately does not offer a blanket `bypassPermissions` mode.
Your options per agent:

| Mode          | Behavior                                                                     |
| ------------- | ---------------------------------------------------------------------------- |
| `default`     | Every command / file write pauses and asks on your phone                     |
| `acceptEdits` | Auto-allows **all** write actions, commands included — the "just do it" mode |
| `plan`        | Read-only; all writes hard-denied                                            |

## Configuration reference

All via environment variables (see `.env.example`):

| Variable                                               | Purpose                                                                                                                                                                                              |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGY_OAUTH_TOKEN_B64`                                  | Antigravity OAuth token (base64) — primary auth                                                                                                                                                      |
| `OAUTH_CREDS_JSON`                                     | `~/.gemini/oauth_creds.json` contents — alternate/additional auth                                                                                                                                    |
| `GIT_USER_NAME` / `GIT_USER_EMAIL`                     | Git identity for agent commits                                                                                                                                                                       |
| `GITHUB_TOKEN`                                         | Enables `gh` CLI and private repo access                                                                                                                                                             |
| `MCP_CONFIG_B64`                                       | Antigravity MCP config (base64). **Caution:** every warm harness runs all configured MCP servers permanently (~100-400MB RAM each). Removing the variable also removes a previously injected config. |
| `GEMINI_API_KEY`                                       | Optional: enables a second "Gemini CLI" agent provider (paid/free-tier [AI Studio](https://aistudio.google.com) key — Gemini CLI no longer serves consumer OAuth accounts)                           |
| `AGY_ACP_TRANSPORT`                                    | `connect` (warm server, default) or `cli` (spawn per prompt: slower, leaner)                                                                                                                         |
| `PASEO_RELAY_ENABLED`                                  | `true` (default) for phone access from anywhere; `false` for LAN/VPN-only                                                                                                                            |
| `PASEO_USE_SUPERVISOR`                                 | `true` restores Paseo's stock supervisor chain (+~325MB RAM)                                                                                                                                         |
| `PASEO_DICTATION_ENABLED` / `PASEO_VOICE_MODE_ENABLED` | `false` by default — `true` makes the daemon download ~1GB of local speech models                                                                                                                    |

## Persistence

The compose file mounts four named volumes. All of them matter — remove one
and some part of your state resets with the container:

| Volume         | Path                        | Holds                                                |
| -------------- | --------------------------- | ---------------------------------------------------- |
| `paseo-home`   | `/root/.paseo`              | Agent registry, pairing keys, daemon config          |
| `gemini-home`  | `/root/.gemini`             | Antigravity conversations, refreshed auth tokens     |
| `acp-sessions` | `/root/.config/antigravity` | Session bindings + chat transcripts (history replay) |
| `workspaces`   | `/root/dev`                 | Your repositories                                    |

## Resource footprint

- **~250MB RAM idle**, ~2-3% CPU
- **+~220MB per workspace** you've prompted since the last restart — the warm
  Antigravity harness is deliberately kept alive so turns stay fast, and it
  does not idle out.
- MCP servers (if configured) add ~100-400MB **each**, per workspace harness.

## Troubleshooting

**Provider shows "Unavailable" / auth warnings in logs** — the entrypoint
runs a startup auth probe; look for `'agy models' hung or failed` in
`docker compose logs`. Re-export credentials from a machine with a working
Antigravity login.

**Slow responses (3-6s instead of ~1.3s)** — the adapter fell back to
spawn-per-prompt mode, usually after an Antigravity update changed its
private API. Check: `docker compose exec paseo grep "harness: ready"
/root/.gemini/agy-agent-acp.log` — no matches means you're on the fallback.
Open an issue with your `agy --version`.

**"Agent not found" after restart** — a volume is missing. All four volumes
in the compose file must be present (see Persistence above).

**High memory** — almost always `MCP_CONFIG_B64`. Each warm harness runs
every configured MCP server as a permanent process. Clear the variable and
restart; the entrypoint removes the stale config automatically.

**Re-pairing** — run `docker compose exec paseo paseo onboard` again on any
new device.

## Design notes

Things this image does — kept here so you know what you're running:

- **Warm-server bridge**: `agy-agent-acp` (pinned to a known-good commit)
  instead of spawn-per-prompt wrappers. RAM pays for latency, knowingly.
- **Local patches** (`patch-agy-adapter.py`, applied at build with hard
  assertions that fail the build if upstream drifts):
  1. Sessions default to _writable_ — the adapter's `allowWriteTools` ACP
     extension is not sent by Paseo, which otherwise leaves every session
     read-only and unable to run commands (including sessions restored after
     a restart).
  2. Chat transcripts are actually recorded — upstream ships store/replay
     machinery for `session/load` but never writes to it, so history was
     lost on every restart.
- **Direct daemon mode**: runs Paseo's daemon worker directly instead of its
  CLI wrapper + supervisor chain (−~325MB RAM). Crash-restart is the
  container runtime's job (`restart: unless-stopped`); pid-locking and
  self-update don't apply to a pinned single-process container.
- **tini as PID 1**: Antigravity and MCP servers leave orphaned children;
  tini reaps them and forwards signals so shutdowns are clean.
- **Process-group cleanup in the auth probe**: `agy` starts every configured
  MCP server on launch; a plain `timeout` would orphan them to spin at 100%
  CPU forever.
- **Speech models off by default**: Paseo otherwise downloads ~1GB of ONNX
  voice models on first start of every fresh container.

## Security notes

- The container runs as root and agents in `acceptEdits` mode execute
  arbitrary commands inside it. Treat the container as the agent's sandbox:
  don't mount anything into it you wouldn't let an agent touch.
- Credentials passed via `.env` are visible in the container environment and
  written to files inside it. Keep the host locked down.
- The Paseo relay is end-to-end encrypted (keys are exchanged during QR
  pairing); disable it and use your own VPN if you prefer
  (`PASEO_RELAY_ENABLED=false`).

## Credits

- [Paseo](https://paseo.sh) — the agent daemon and mobile/web app
- [jameslunardi/agy-agent-acp](https://github.com/jameslunardi/agy-agent-acp) — the warm-server ACP adapter
- Google Antigravity — the agent itself

MIT licensed. Not affiliated with Google or Paseo.
