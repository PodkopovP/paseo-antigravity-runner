# Paseo + Google Antigravity headless runner
#
# Antigravity is bridged into Paseo via agy-agent-acp, which keeps one warm
# `agy` language server per workspace and drives it over its local Connect
# API (~1.3s/turn) instead of spawning a fresh `agy` process per prompt
# (~3.4s/turn). If the private Connect API breaks after an agy upgrade, the
# adapter degrades to the slower per-turn CLI transport automatically.
FROM ubuntu:22.04

# Avoid tzdata interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# --- Base dependencies ------------------------------------------------------

RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    gpg \
    python3 \
    python3-pip \
    tini \
    unzip \
  && rm -rf /var/lib/apt/lists/*

# --- GitHub CLI (gh) --------------------------------------------------------

RUN mkdir -p -m 755 /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# --- Node.js 20 + Paseo CLI ---------------------------------------------------

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @getpaseo/cli

# --- Antigravity CLI (agy) ----------------------------------------------------

RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

# --- Antigravity ACP adapter (agy-agent-acp) -----------------------------------
# Pinned to a known-good commit; bump deliberately after testing.
# Ubuntu 22.04's pip (22.0.2) is too old for this package's PEP 621/639
# metadata — it silently builds "UNKNOWN-0.0.0" with no console script.
# Upgrade pip first.

RUN pip3 install --no-cache-dir --upgrade pip \
  && pip3 install --no-cache-dir \
    "git+https://github.com/jameslunardi/agy-agent-acp@8ff8abbf55434caf93f44ffc374e0ec6bbc1ca55" \
  && agy-agent-acp --help >/dev/null

# Apply local patches to the pinned adapter — write-tools defaults (Paseo
# never sends the adapter-specific allowWriteTools extension, and restored
# sessions reverted to read-only after restarts) and transcript persistence
# (upstream stores/replays chat history but never records it). The script
# fails the build if upstream code drifts under the pin.
COPY patch-agy-adapter.py /tmp/patch-agy-adapter.py
RUN python3 /tmp/patch-agy-adapter.py \
  && python3 -m py_compile \
    /usr/local/lib/python3.10/dist-packages/agy_agent_acp/server.py \
    /usr/local/lib/python3.10/dist-packages/agy_agent_acp/session_store.py \
    /usr/local/lib/python3.10/dist-packages/agy_agent_acp/adapter.py \
  && rm /tmp/patch-agy-adapter.py

# --- Gemini CLI (optional fast lane) --------------------------------------------
# Persistent ACP agent, but since 2026-06-18 it only serves paid API keys /
# Code Assist licenses. The provider is enabled at runtime only when
# GEMINI_API_KEY is set.

RUN npm install -g @google/gemini-cli@0.54.4

# --- Runtime configuration ----------------------------------------------------
# Speech: dictation and voice mode default to ON with the "local" provider,
# which makes the daemon download ~1GB of ONNX speech models (Kokoro TTS +
# Parakeet STT) in the background on every fresh container start, and load
# them into memory when used. Off by default on a headless runner; override
# via environment if you use Paseo's voice features with a cloud provider.
#
# Relay: enables Paseo's end-to-end-encrypted relay so the mobile/web app can
# reach this daemon from anywhere without exposing ports. Set to false if you
# only connect over LAN/VPN (e.g. Tailscale) directly to the daemon port.

ENV PASEO_DICTATION_ENABLED=false \
    PASEO_VOICE_MODE_ENABLED=false \
    PASEO_RELAY_ENABLED=true

# --- Entrypoint ----------------------------------------------------------------

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# tini as PID 1: reaps zombie processes (orphaned npm exec/MCP children
# otherwise accumulate as <defunct>) and forwards signals properly.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
