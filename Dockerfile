# Antigravity Remote Control (self-hosted)
#
# Runs the official Antigravity CLI remote-control daemon (`agy
# --remote-control`, https://antigravity.google/docs/remote-control/) headless
# in a container. The daemon connects *outbound* to Google's Remote Control
# service and you drive it from the hosted dashboard at
# https://antigravity.google.com — no inbound ports, tunnels, or proxies.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    gpg \
    jq \
    procps \
    python3 \
    tini \
    zstd \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI (for the agents' git workflows inside workspaces).
RUN mkdir -p -m 755 /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

# Official Antigravity CLI (checksum-verified flat native build). The CLI
# self-updates at runtime, so the version baked here only has to be recent
# enough to update itself.
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh \
  && bash /tmp/agy-install.sh --dir /usr/local/bin \
  && rm -f /tmp/agy-install.sh \
  && test -x /usr/local/bin/agy

# Official Claude Code CLI (native build).
RUN curl -fsSL https://claude.ai/install.sh | bash \
  && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
  && test -x /usr/local/bin/claude

# Runtime environment
ENV PATH="/root/.local/bin:${PATH}" \
    AGY_CLI_DISABLE_AUTO_UPDATE=false \
    CLAUDE_CONFIG_DIR=/root/.claude

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# tini as PID 1: reaps the sidecar/MCP children the daemons spawn and forwards
# signals so `docker stop` shuts the tree down cleanly.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh", "antigravity"]

