# Antigravity Remote (self-hosted)
#
# Runs the Antigravity 2.0 hub language server headless in standalone "hub"
# mode. That one process serves the full Antigravity web UI and the agent
# backend on a single local HTTP port. A tiny Node reverse proxy rewrites the
# Host/Origin headers so a Cloudflare Tunnel can reach it (the hub 401s any
# non-localhost Host), and cloudflared publishes it to the edge.
#
# Build:
#   docker compose build \
#     --build-arg ANTIGRAVITY_HUB_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/<ver>-<build>/linux-x64/Antigravity.tar.gz"
#
# The URL is the Linux tarball of the *Antigravity 2.0* app (the hub / agent
# manager) from the "Antigravity 2.0" section of
# https://antigravity.google/download. The version-pinned URL changes each
# release, so it must be supplied at build time. Note that
# https://antigravity.google/download/linux serves the Antigravity *IDE*
# instead, which this build rejects (see the guard below).

# --- Stage 1: fetch and extract the hub language server ---------------------
FROM ubuntu:22.04 AS fetch

ARG ANTIGRAVITY_HUB_URL
ARG ANTIGRAVITY_HUB_SHA512=""

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN set -eux; \
  if [ -z "${ANTIGRAVITY_HUB_URL}" ]; then \
    echo "ERROR: ANTIGRAVITY_HUB_URL build-arg is required."; \
    echo "Grab the Antigravity 2.0 (hub) Linux tarball URL from the"; \
    echo "'Antigravity 2.0' section of https://antigravity.google/download"; \
    exit 1; \
  fi; \
  curl -fsSL -o payload "${ANTIGRAVITY_HUB_URL}"; \
  if [ -n "${ANTIGRAVITY_HUB_SHA512}" ]; then \
    echo "${ANTIGRAVITY_HUB_SHA512}  payload" | sha512sum -c -; \
  fi; \
  mkdir -p extracted; \
  case "${ANTIGRAVITY_HUB_URL}" in \
    *.deb) dpkg-deb -x payload extracted ;; \
    *)     tar -xf payload -C extracted ;; \
  esac; \
  ls_bin="$(find extracted -type f \( -name language_server -o -name 'language_server_*' \) | head -n1)"; \
  if [ -z "${ls_bin}" ]; then echo "language_server not found in archive"; exit 1; fi; \
  echo "Found language server at ${ls_bin}"; \
  # Guard: only the "Antigravity" (hub) desktop app embeds the web bundle. The \
  # "Antigravity IDE" (VS Code fork) build omits it and fatals at runtime with \
  # 'embedded web bundle not available ... without include_agyhub_bundle tag'. \
  # Reject that build now with an actionable message instead of a crash loop. \
  if grep -aq "embedded web bundle not available" "${ls_bin}"; then \
    echo "ERROR: this archive is the Antigravity *IDE* (VS Code fork) build."; \
    echo "Its language server has no embedded web UI bundle and cannot serve"; \
    echo "the hub. You need the *Antigravity* desktop app (com.google.antigravity,"; \
    echo "the agent manager that serves the local web UI), Linux build."; \
    exit 1; \
  fi; \
  if ! grep -aq "compiled_tailwind.css" "${ls_bin}"; then \
    echo "ERROR: language server does not appear to embed the hub web bundle."; \
    exit 1; \
  fi; \
  bindir="$(dirname "${ls_bin}")"; \
  echo "Found hub binaries in ${bindir}"; \
  mkdir -p /opt/antigravity/bin; \
  cp -a "${bindir}/." /opt/antigravity/bin/; \
  cp -a "${ls_bin}" /opt/antigravity/bin/language_server; \
  chmod +x /opt/antigravity/bin/language_server; \
  [ -f /opt/antigravity/bin/webm_encoder ] && chmod +x /opt/antigravity/bin/webm_encoder || true

# --- Stage 2: runtime image -------------------------------------------------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    gpg \
    tini \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI (for the agent's git workflows inside workspaces).
RUN mkdir -p -m 755 /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# Node.js 20 — only used for the ~80-line dependency-free reverse proxy.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

# cloudflared — publishes the proxy to the Cloudflare edge via a tunnel token.
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL -o /usr/local/bin/cloudflared \
     "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" \
  && chmod +x /usr/local/bin/cloudflared

# Hub language server from stage 1.
COPY --from=fetch /opt/antigravity/bin /opt/antigravity/bin
RUN ln -sf /opt/antigravity/bin/language_server /usr/local/bin/language_server
ENV LANGUAGE_SERVER_BIN=/opt/antigravity/bin/language_server

# App code.
WORKDIR /app
COPY proxy.js /app/proxy.js
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Hub binds loopback on HUB_HTTP_PORT; the proxy listens on PROXY_LISTEN_PORT.
ENV HUB_HTTP_PORT=8090 \
    PROXY_LISTEN_PORT=8765

EXPOSE 8765

# tini as PID 1: reaps the sidecar/MCP children the hub spawns and forwards
# signals so `docker stop` shuts the tree down cleanly.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
