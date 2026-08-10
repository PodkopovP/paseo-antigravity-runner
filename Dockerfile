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
ENV PATH="/root/.local/bin:/root/.bun/bin:${PATH}"

# Install Node.js (v20)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs

# Install Paseo globally
RUN npm install -g @getpaseo/cli

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
  if [ -n "$GITHUB_TOKEN" ]; then\n\
  gh auth setup-git\n\
  echo "Downloading AGY CLI engine..."\n\
  mkdir -p /root/.local/bin\n\
  gh release download v1.0.13 -R google-antigravity/antigravity-cli -p "agy_cli_linux_x64.tar.gz" -O /tmp/agy.tar.gz\n\
  tar -xzf /tmp/agy.tar.gz -C /root/.local/bin\n\
  chmod +x /root/.local/bin/agy\n\
  export AGY_BIN=/root/.local/bin/agy\n\
  fi\n\
  echo "Installing AGY CLI and setting up bridge..."\n\
  npx --yes @nghichcode/paseo_agy\n\
  rm -f /root/.paseo/paseo.pid /root/.paseo/daemon.sock\n\
  exec paseo start --foreground' > /entrypoint.sh && chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
