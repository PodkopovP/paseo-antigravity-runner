#!/usr/bin/env bash
# ==============================================================================
# Antigravity Remote (self-hosted) — One-Line Installer & Updater
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
#   OR
#   ./setup.sh
# ==============================================================================

set -euo pipefail

BOLD="\033[1m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; RED="\033[0;31m"; BLUE="\033[0;34m"; NC="\033[0m"
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
fatal()   { error "$1"; exit 1; }

echo -e "${BOLD}"
echo "============================================================"
echo "  🛰  Antigravity Remote (self-hosted) — Setup & Update"
echo "============================================================"
echo -e "${NC}"

# 1. Pre-flight checks
info "Checking system prerequisites..."
command -v docker >/dev/null 2>&1 || fatal "Docker is not installed: https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || fatal "Docker daemon is not running or you lack permissions (docker group / sudo)."

COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then COMPOSE_CMD="docker compose";
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE_CMD="docker-compose";
else fatal "Docker Compose is not installed: https://docs.docker.com/compose/install/"; fi
command -v git >/dev/null 2>&1 || fatal "Git is not installed."
success "Prerequisites check passed (using '$COMPOSE_CMD')."

# 2. Repository directory management
REPO_NAME="paseo-antigravity-runner"
REPO_URL="https://github.com/PodkopovP/paseo-antigravity-runner.git"
if [[ -f "docker-compose.yml" && -f "Dockerfile" ]]; then
    info "Running inside repository directory '$(pwd)'."
    [[ -d ".git" ]] && { info "Updating repository code..."; git pull --rebase || warn "git pull failed; continuing."; }
elif [[ -d "$REPO_NAME" && -f "$REPO_NAME/docker-compose.yml" ]]; then
    info "Found '$REPO_NAME'. Entering..."; cd "$REPO_NAME"
    [[ -d ".git" ]] && { info "Updating repository code..."; git pull --rebase || warn "git pull failed; continuing."; }
else
    info "Cloning repository from $REPO_URL..."; git clone "$REPO_URL" "$REPO_NAME"; cd "$REPO_NAME"
fi

# 3. Environment & credential setup
if [[ ! -f ".env" ]]; then
    [[ -f ".env.example" ]] || fatal ".env.example not found! Repository may be corrupted."
    info "Creating .env from .env.example..."; cp .env.example .env
fi

# Hub download URL (required at build time).
if ! grep -qE '^ANTIGRAVITY_HUB_URL=[^[:space:]]+' .env 2>/dev/null; then
    warn "------------------------------------------------------------"
    warn "ANTIGRAVITY_HUB_URL is not set in .env."
    warn "Grab the 'Antigravity 2.0' Linux tarball URL from:"
    warn "  https://antigravity.google/download   (the Antigravity 2.0 section —"
    warn "  NOT /download/linux, which serves the IDE build this image rejects)"
    warn "and set ANTIGRAVITY_HUB_URL= in .env, then re-run this script."
    warn "------------------------------------------------------------"
    exit 1
fi

# Antigravity credentials.
if grep -qE '^(OAUTH_CREDS_JSON|JETSKI_STANDALONE_OAUTH_TOKEN_B64|AGY_OAUTH_TOKEN_B64)=[^[:space:]]+' .env 2>/dev/null; then
    success "Antigravity credentials found in .env."
elif [[ -f "$HOME/.gemini/oauth_creds.json" || -f "$HOME/.gemini/jetski-standalone-oauth-token" || -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]]; then
    info "Found local Antigravity credentials — exporting to .env..."
    bash ./scripts/export-credentials.sh >> .env && success "Credentials auto-exported into .env."
else
    warn "------------------------------------------------------------"
    warn "NO ANTIGRAVITY CREDENTIALS DETECTED."
    warn "The UI will load but Antigravity will be unavailable until auth is set."
    warn "On a logged-in machine:  ./scripts/export-credentials.sh >> .env"
    warn "then:  $COMPOSE_CMD up -d"
    warn "------------------------------------------------------------"
fi

# 4. Build & launch (URL comes from .env via ANTIGRAVITY_HUB_URL).
info "Building and starting container with $COMPOSE_CMD..."
$COMPOSE_CMD up -d --build

# 5. Next steps
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 Antigravity Remote is up! ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
if grep -qE '^CLOUDFLARE_TUNNEL_TOKEN=[^[:space:]]+' .env 2>/dev/null; then
  echo -e "${BOLD}cloudflared is running in-container.${NC}"
  echo -e "In the Cloudflare Zero Trust dashboard:"
  echo -e "  1. Point your tunnel's public hostname at ${BLUE}http://localhost:8765${NC}"
  echo -e "  2. Add an ${BOLD}Access${NC} application over that hostname"
  echo -e "  3. Require ${BOLD}WARP${NC} / your identity provider in the Access policy"
  echo -e "Then open the hostname on your phone — it's the full Antigravity UI."
else
  echo -e "No CLOUDFLARE_TUNNEL_TOKEN set. The host-rewrite proxy is on ${BLUE}127.0.0.1:8765${NC}."
  echo -e "Reach it over LAN/VPN, or set CLOUDFLARE_TUNNEL_TOKEN in .env and re-run."
fi
echo -e "============================================================"
echo ""
