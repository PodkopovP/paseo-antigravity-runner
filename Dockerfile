# We use a Debian/Ubuntu base to easily install dependencies
FROM ubuntu:22.04

# Avoid tzdata interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required by the paseo_agy bridge)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Node.js (v20)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Paseo globally
RUN npm install -g paseo

# Run the paseo_agy installer to download the AGY CLI and set up the ACP bridge
RUN npx --yes @nghichcode/paseo_agy

# Define standard env variables (populate these in Coolify's Environment Variables tab)
# The Antigravity CLI (agy) needs to authenticate. Since you can't run `agy auth login` 
# in a browser on a headless VM, you must provide your API key.
ENV GOOGLE_API_KEY=""

# The entrypoint runs Paseo's daemon
CMD ["paseo", "start"]
