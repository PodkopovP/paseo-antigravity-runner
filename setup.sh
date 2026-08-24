#!/usr/bin/env bash
# ==============================================================================
# Antigravity Remote Control (self-hosted) — One-Line Installer & Updater
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
echo "  🛰  Antigravity Remote Control (self-hosted) — Setup"
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

# 3. Environment setup
if [[ ! -f ".env" ]]; then
    [[ -f ".env.example" ]] || fatal ".env.example not found! Repository may be corrupted."
    info "Creating .env from .env.example..."; cp .env.example .env
fi

# 4. Build
info "Building image with $COMPOSE_CMD..."
$COMPOSE_CMD build

# 5. First-time sign-in
# A previous in-container sign-in lives in the gemini-home volume.
HAS_CREDS=false
if $COMPOSE_CMD run --rm --no-deps -T antigravity-remote \
     test -s /root/.gemini/jetski-standalone-oauth-token >/dev/null 2>&1; then
    success "Existing sign-in found in the container volume."
    HAS_CREDS=true
elif [[ -t 0 ]]; then
    info "Not signed in yet — starting one-time interactive sign-in..."
    $COMPOSE_CMD run --rm antigravity-remote && HAS_CREDS=true || \
        warn "Sign-in did not complete; you can retry later (see below)."
fi

# 6. Launch
info "Starting container with $COMPOSE_CMD..."
$COMPOSE_CMD up -d

# 7. Next steps
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 Antigravity Remote Control is up! ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
if [[ "$HAS_CREDS" == "true" ]]; then
  echo -e "Open ${BLUE}https://antigravity.google.com${NC} with the same Google"
  echo -e "Account to see this instance and drive it from any browser."
else
  echo -e "${BOLD}Not signed in yet.${NC} Complete the one-time sign-in with:"
  echo -e "  ${BLUE}$COMPOSE_CMD run --rm antigravity-remote${NC}"
  echo -e "then restart the daemon:"
  echo -e "  ${BLUE}$COMPOSE_CMD up -d --force-recreate${NC}"
fi
echo -e "Logs:   ${BLUE}$COMPOSE_CMD logs -f antigravity-remote${NC}"
echo -e "============================================================"
echo ""
