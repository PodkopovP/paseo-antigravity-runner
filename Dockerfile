# Paseo + Google Antigravity headless runner
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

# --- Bun (needed to compile the paseo_agy bridge binary) ---------------------

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.local/bin:/root/.bun/bin:${PATH}"

# --- Node.js 20 + Paseo CLI ---------------------------------------------------

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @getpaseo/cli

# --- Antigravity bridge (paseo_agy) -------------------------------------------
# Run before agy is installed so setup skips the hanging 'agy models' command
# and falls back to its built-in model list.

RUN npx --yes @nghichcode/paseo_agy

# --- Antigravity CLI (agy) ----------------------------------------------------

RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# --- Gemini CLI -----------------------------------------------------------------
# Runs as a persistent ACP agent (gemini --acp): no per-prompt process spawn,
# real streaming. Much lower latency than the agy one-shot bridge. Installed
# globally so agent startup doesn't pay an npx download.

RUN npm install -g @google/gemini-cli@0.54.4

# --- Runtime configuration ----------------------------------------------------
# Disable dictation and voice mode. They default to ON with the "local"
# provider, which makes the daemon download ~1GB of ONNX speech models
# (Kokoro TTS + Parakeet STT) in the background on every fresh container
# start, and load them into memory when used. Useless on a headless runner.

ENV PASEO_DICTATION_ENABLED=false \
    PASEO_VOICE_MODE_ENABLED=false

# --- Entrypoint ----------------------------------------------------------------

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
