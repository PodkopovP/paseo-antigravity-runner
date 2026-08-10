# We use a Debian/Ubuntu base to easily install dependencies
FROM ubuntu:22.04

# Avoid tzdata interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    git \
    build-essential \
    gpg \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh)
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install gh -y \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required by the paseo_agy bridge)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Node.js (v20)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Paseo globally
RUN npm install -g @getpaseo/cli

# Run the paseo_agy installer to download the AGY CLI and set up the ACP bridge
RUN npx --yes @nghichcode/paseo_agy

# Support OAuth credentials via an environment variable
ENV OAUTH_CREDS_JSON=""

# Create an entrypoint script to handle auth credentials
RUN echo '#!/bin/bash\n\
if [ -n "$OAUTH_CREDS_JSON" ]; then\n\
  mkdir -p /root/.gemini\n\
  echo "$OAUTH_CREDS_JSON" > /root/.gemini/oauth_creds.json\n\
  echo "Injected OAuth credentials for Antigravity CLI."\n\
fi\n\
if [ -n "$AGY_OAUTH_TOKEN_B64" ]; then\n\
  mkdir -p /root/.gemini/antigravity-cli\n\
  echo "$AGY_OAUTH_TOKEN_B64" | base64 -d > /root/.gemini/antigravity-cli/antigravity-oauth-token\n\
  chmod 600 /root/.gemini/antigravity-cli/antigravity-oauth-token\n\
  echo "Injected base64 OAuth token for Antigravity CLI."\n\
fi\n\
if [ -n "$MCP_CONFIG_B64" ]; then\n\
  mkdir -p /root/.gemini/config\n\
  echo "$MCP_CONFIG_B64" | base64 -d > /root/.gemini/config/mcp_config.json\n\
  echo "Injected MCP configuration."\n\
fi\n\
if [ -n "$GIT_USER_NAME" ]; then\n\
  git config --global user.name "$GIT_USER_NAME"\n\
fi\n\
if [ -n "$GIT_USER_EMAIL" ]; then\n\
  git config --global user.email "$GIT_USER_EMAIL"\n\
fi\n\
rm -f /root/.paseo/daemon.pid /root/.paseo/daemon.sock\n\
exec paseo start --foreground' > /entrypoint.sh && chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
