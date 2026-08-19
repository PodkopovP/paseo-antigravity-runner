# Antigravity Remote — self-hosted

Run **Google Antigravity** headless on your own server and use its **built-in
web UI** from your phone or any browser — secured with a **Cloudflare Tunnel +
WARP**, no inbound ports open.

This replaces the old Paseo + `agy-agent-acp` bridge. Antigravity 2.0 already
ships a complete remote web experience: the hub language server, run in
`--standalone --subclient_type hub` mode, serves the full Antigravity UI *and*
the agent backend on one local HTTP port. We just run that in a container,
front it with a header-rewriting proxy, and publish it through Cloudflare.

```
┌──────────────┐   HTTPS    ┌ Cloudflare edge ┐   tunnel   ┌──────────── your server ────────────┐
│ phone/browser│ ─────────► │ Access + WARP    │ ─────────► │ cloudflared → proxy :8765 → hub LS  │
└──────────────┘            └──────────────────┘  outbound  │  (rewrites Host/Origin → 127.0.0.1) │
                                                             └──────────────────────────────────────┘
```

## Why the proxy?

The hub server binds loopback and **rejects any request whose `Host` header
isn't `localhost`/`127.0.0.1` with a `401`** (a foreign `Origin` is fine — only
`Host` is checked). A Cloudflare Tunnel forwards the public hostname in `Host`,
which the hub would reject. `proxy.js` (dependency-free Node, HTTP + WebSocket)
rewrites `Host`/`Origin` to the loopback address so the browser can talk to
`https://<your-hostname>/` while the hub only ever sees `127.0.0.1`.

---

## ⚡ Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
```

The script checks prerequisites, creates `.env`, auto-exports local Antigravity
credentials if present, builds, and starts the container.

You must set two things in `.env` before it can build/run:

1. **`ANTIGRAVITY_HUB_URL`** — the Linux tarball of the **Antigravity 2.0**
   app (the hub / agent manager) from the *Antigravity 2.0* section of
   <https://antigravity.google/download>, e.g.
   `https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-6512087774658560/linux-x64/Antigravity.tar.gz`.
   The URL is version-pinned and changes each release, so it can't be
   hardcoded. ⚠️ Don't use `antigravity.google/download/linux` — that page
   serves the Antigravity **IDE** (VS Code fork), whose language server has no
   embedded web UI; the build rejects it with an explanatory error.
2. **Antigravity credentials** — `./scripts/export-credentials.sh >> .env`
   (run on a machine already logged in to Antigravity).

Optionally set **`CLOUDFLARE_TUNNEL_TOKEN`** to publish through Cloudflare.

---

## 🛠 Manual setup

```bash
git clone https://github.com/PodkopovP/paseo-antigravity-runner.git
cd paseo-antigravity-runner
cp .env.example .env

# 1. Hub binary: paste the "Antigravity 2.0" Linux tarball URL into .env
#    (from https://antigravity.google/download — NOT /download/linux, that's the IDE)
#    ANTIGRAVITY_HUB_URL=https://storage.googleapis.com/antigravity-public/antigravity-hub/<ver>-<build>/linux-x64/Antigravity.tar.gz

# 2. Credentials (run on a logged-in machine):
./scripts/export-credentials.sh >> .env

# 3. Cloudflare tunnel token (optional, from Zero Trust > Networks > Tunnels):
#    CLOUDFLARE_TUNNEL_TOKEN=...

# 4. Build & launch
docker compose up -d --build
```

---

## 🔒 Securing with Cloudflare Tunnel + WARP

With `CLOUDFLARE_TUNNEL_TOKEN` set, `cloudflared` runs inside the container and
connects outbound only. In the **Cloudflare Zero Trust** dashboard:

1. **Tunnel route** — point your tunnel's public hostname at
   `http://localhost:8765`.
2. **Access application** — add a self-hosted Access app over that hostname so
   every request is authenticated at the edge.
3. **WARP / identity** — require WARP enrollment (or your IdP) in the Access
   policy, so only your enrolled devices reach the UI.

Then open the hostname on your phone — it's the full Antigravity web UI.

Without a token, only the local `127.0.0.1:8765` proxy port is exposed; reach
it over LAN/VPN (e.g. Tailscale) or run your own tunnel.

---

## 🔄 Updating

```bash
./setup.sh                      # pulls, rebuilds, restarts
# or
git pull && docker compose up -d --build
```

To pick up a new Antigravity release, update `ANTIGRAVITY_HUB_URL` in `.env`
and rebuild.

---

## ⚙️ Configuration reference

| Variable | Purpose |
| --- | --- |
| `ANTIGRAVITY_HUB_URL` | **(required, build-time)** Linux Antigravity 2.0 archive URL |
| `ANTIGRAVITY_HUB_SHA512` | optional archive checksum |
| `OAUTH_CREDS_JSON` | `~/.gemini/oauth_creds.json` contents |
| `JETSKI_STANDALONE_OAUTH_TOKEN_B64` | base64 of `~/.gemini/jetski-standalone-oauth-token` |
| `AGY_OAUTH_TOKEN_B64` | base64 of `~/.gemini/antigravity-cli/antigravity-oauth-token` |
| `GOOGLE_ACCOUNTS_JSON` | `~/.gemini/google_accounts.json` contents |
| `CLOUDFLARE_TUNNEL_TOKEN` | Cloudflare tunnel token; enables in-container `cloudflared` |
| `AGY_HOSTNAME` | hostname label for this instance (default: container hostname) |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | git identity inside workspaces |
| `GITHUB_TOKEN` | lets the agent push / open PRs |
| `HUB_HTTP_PORT` | internal hub HTTP port (default `8090`) |
| `PROXY_LISTEN_PORT` | proxy / published port (default `8765`) |

---

## 🧩 How it works

- **`language_server --standalone --subclient_type hub`** — one process, the
  whole Antigravity 2.0 experience (web UI assets are embedded in the binary),
  on `HUB_HTTP_PORT`. A per-start CSRF token is embedded into the served HTML,
  so the browser picks it up automatically.
- **`proxy.js`** — rewrites `Host`/`Origin` to `127.0.0.1` for HTTP and
  WebSocket upgrades so tunnelled traffic passes the hub's Host check.
- **`cloudflared`** — outbound tunnel to the Cloudflare edge; secured by Access
  + WARP.
- **`entrypoint.sh`** — injects credentials, enables the built-in remote-control
  setting in `~/.gemini/config/config.json`, launches and supervises the three
  processes.
