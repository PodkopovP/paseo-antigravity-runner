# Antigravity Remote Control — self-hosted

Run the **official Antigravity Remote Control daemon** headless on your own
server in Docker, and drive it from your phone or any browser via Google's
hosted [Remote Control dashboard](https://antigravity.google.com) —
**outbound connections only**: no open ports, no tunnel, no reverse proxy.

Antigravity now ships remote control natively
(<https://antigravity.google/docs/remote-control/>): `agy --remote-control`
connects a machine to the dashboard, where the full agent-manager UI runs
against it. This repo simply wraps that daemon in a container so it survives
reboots, stays isolated from the host, and carries git + GitHub CLI for the
agents' workspaces.

```
┌──────────────┐   HTTPS   ┌ antigravity.google.com ┐   outbound   ┌── your server ───────┐
│ phone/browser│ ────────► │ Remote Control          │ ◄─────────── │ agy --remote-control │
└──────────────┘           │ dashboard (Google)      │              │     (in Docker)      │
                           └──────────────────────────┘              └──────────────────────┘
```

---

## ⚡ Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
```

The script checks prerequisites, creates `.env`, builds, walks you through
the one-time sign-in if needed, and starts the container. Then open
<https://antigravity.google.com> with the same Google Account — your
instance appears in the list.

---

## 🛠 Manual setup

```bash
git clone https://github.com/PodkopovP/paseo-antigravity-runner.git
cd paseo-antigravity-runner
cp .env.example .env          # everything in it is optional
docker compose build
```

Then do the one-time sign-in (prints a URL to open; paste the code back):

```bash
docker compose run --rm antigravity-remote
```

And launch:

```bash
docker compose up -d
```

The auth token lives in the `gemini-home` volume, so sign-in is one-time; the
daemon refreshes it automatically from then on.

---

## 🔄 Updating

The Antigravity CLI self-updates in the background while the daemon runs, and
any downloaded update is applied on container start — so:

```bash
docker compose restart        # apply a pending CLI update
./setup.sh                    # update this repo, rebuild, restart
```

---

## ⚙️ Configuration reference

All optional, set in `.env`:

| Variable | Purpose |
| --- | --- |
| `AGY_HOSTNAME` | instance name shown in the dashboard (default: saved name, or auto-generated) |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | git identity inside workspaces |
| `GITHUB_TOKEN` | lets the agent push / open PRs |

Sign-in is deliberately **not** configured via `.env`: the one-time
interactive sign-in stores the auth token in the `gemini-home` volume, and
the daemon refreshes it from then on.

---

## 🧩 How it works

- **`agy --remote-control`** — the official Antigravity CLI daemon
  (installed at build time from <https://antigravity.google/cli/install.sh>).
  It registers this machine with Google's Remote Control service over an
  outbound connection and executes agent tasks locally in `/root/dev`.
- **`entrypoint.sh`** — configures git/GitHub, applies any pending CLI
  update (`agy --bg-updater`, like the official systemd unit), handles the
  one-time interactive sign-in, then `exec`s the daemon.
- **Access control** is Google's: the dashboard requires the same Google
  Account that signed in the daemon.

---

## 🧳 Migrating from the hub/proxy version

Earlier versions of this repo self-hosted the Antigravity 2.0 hub web UI
behind a host-rewriting proxy and a Cloudflare Tunnel. The official daemon
replaces all of that:

- `git pull && docker compose up -d --build` — done. Your sign-in and state
  carry over via the `gemini-home` volume.
- These `.env` entries are now ignored and can be deleted:
  `ANTIGRAVITY_HUB_URL`, `ANTIGRAVITY_HUB_SHA512`, `CLOUDFLARE_TUNNEL_TOKEN`.
- The Cloudflare tunnel, Access application, and the `127.0.0.1:8765` port
  mapping are no longer used and can be decommissioned.
