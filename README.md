# Antigravity on your phone — self-hosted Paseo runner

Run **Google Antigravity** on your own server and steer coding agents directly from the **[Paseo](https://paseo.sh)** mobile app or web interface.

```
┌──────────────┐   E2EE relay    ┌────────────────────── your server ──────────────────────┐
│  Paseo app   │ ◄─────────────► │  Paseo daemon ◄─ACP─► agy-agent-acp ◄─► warm agy        │
│ (phone/web)  │  (or LAN/VPN)   │                        (adapter)        language server │
└──────────────┘                 └──────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start (1-Minute Setup)

Run this one-line command on your Linux server or host machine:

```bash
curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
```

The setup script automatically checks prerequisites (Docker, Compose, Git), sets up configuration, auto-detects local Antigravity credentials, builds the container, and starts the runner.

### Pair your device

Once setup completes, pair your phone or browser by running:

```bash
docker compose exec paseo paseo-pair
```

Scan the QR code or open the pairing link in the **[Paseo app](https://app.paseo.sh)**. Pairing is end-to-end encrypted, and no inbound ports need to be open on your server.

---

## 🛠️ Manual Setup

If you prefer to set up manually step-by-step:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/PodkopovP/paseo-antigravity-runner.git
   cd paseo-antigravity-runner
   cp .env.example .env
   ```

2. **Export Antigravity credentials:**
   Run this on a machine where you are logged in to Antigravity (`agy` CLI or IDE):
   ```bash
   ./scripts/export-credentials.sh >> .env
   ```

3. **Build and launch:**
   ```bash
   docker compose up -d --build
   ```

4. **Pair your phone:**
   ```bash
   docker compose exec paseo paseo-pair
   ```

---

## 🔄 Updating the Runner

To update to the latest version, simply run the setup script again:

```bash
./setup.sh
```

Or manually pull changes and rebuild:
```bash
git pull
docker compose up -d --build
```

---

## 🔒 Permission Modes

Choose how autonomous your agent should be when working on repositories:

| Mode          | Behavior                                                                     |
| ------------- | ---------------------------------------------------------------------------- |
| `default`     | Every command and file write asks permission on your phone                   |
| `acceptEdits` | Auto-allows file modifications and commands ("just do it" mode)             |
| `plan`        | Read-only mode; all write actions are blocked                               |

---

## ⚙️ Configuration Reference

Configure settings in `.env` (see `.env.example`):

| Variable                                               | Description                                                                                                                                                                                          | Default                                     |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `AGY_OAUTH_TOKEN_B64`                                  | Antigravity OAuth token (base64)                                                                                                                                                                     | Extracted via `export-credentials.sh`       |
| `OAUTH_CREDS_JSON`                                     | `~/.gemini/oauth_creds.json` contents (raw JSON)                                                                                                                                                     | Extracted via `export-credentials.sh`       |
| `GIT_USER_NAME` / `GIT_USER_EMAIL`                     | Git author identity for agent commits                                                                                                                                                                | Optional                                    |
| `GITHUB_TOKEN`                                         | Enables `gh` CLI and private repo access                                                                                                                                                             | Optional                                    |
| `MCP_CONFIG_B64`                                       | Optional Antigravity MCP config (base64)                                                                                                                                                             | Optional                                    |
| `GEMINI_API_KEY`                                       | Optional Gemini API key to enable Gemini CLI provider                                                                                                                                                | Optional                                    |
| `PASEO_RELAY_ENABLED`                                  | Set `false` for LAN/VPN-only access without relay                                                                                                                                                     | `true`                                      |

---

## ❓ Frequently Asked Questions

<details>
<summary><b>Provider shows "Unavailable" or auth errors?</b></summary>

The entrypoint probes Antigravity auth on startup. Check container logs:
```bash
docker compose logs -f paseo
```
If credentials expired, re-run `./scripts/export-credentials.sh >> .env` on your logged-in machine and restart the container: `docker compose restart`.
</details>

<details>
<summary><b>New Gemini models missing from the model picker?</b></summary>

The picker is built from `agy models` output captured at container start.
Restart the container to refresh it (`docker compose restart`). If `agy models`
itself doesn't list the new model yet, rebuild to pull a newer `agy`:

```bash
docker compose build --build-arg AGY_REFRESH=$(date +%s)
docker compose up -d
```
</details>

<details>
<summary><b>How much RAM does this use?</b></summary>

- **~250MB RAM idle**
- **+~220MB per workspace** active since last restart (keeps warm Antigravity language server active for ~1.3s response time).
</details>

<details>
<summary><b>How do persistent volumes work?</b></summary>

The container uses 4 Docker named volumes:
- `paseo-home` (`/root/.paseo`): Pairing keys & agent registry
- `gemini-home` (`/root/.gemini`): Conversations & refreshed auth tokens
- `acp-sessions` (`/root/.config/antigravity`): History & transcripts
- `workspaces` (`/root/dev`): Your cloned repositories
</details>

<details>
<summary><b>Technical Architecture & Local Patches (Click to expand)</b></summary>

- **Warm-server bridge**: Uses [`agy-agent-acp`](https://github.com/jameslunardi/agy-agent-acp) to maintain a warm language server per workspace (~1.3s/turn vs ~3.5s per turn cold start).
- **Local patches (`patch-agy-adapter.py`)**:
  1. Default sessions to **writable** (prevents restored sessions reverting to read-only after container restarts).
  2. Enables **transcript persistence** so chat history replays correctly when re-opening sessions in the app.
  3. **Live model picker** — the adapter's hardcoded model dropdown is replaced with one built from `agy models` output captured at each container start, so new models appear without an adapter update.
- **Direct daemon worker**: Runs Paseo's daemon worker directly under `tini` without extra supervisor overhead (−~325MB RAM).
</details>

---

## 📜 License

MIT License. Not affiliated with Google or Paseo.
