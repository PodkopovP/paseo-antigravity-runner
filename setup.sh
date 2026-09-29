#!/usr/bin/env bash
# ==============================================================================
# Antigravity & Claude Remote Control (self-hosted) — Setup & Updater
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
echo "  🛰  Antigravity + Claude Remote Control (self-hosted)"
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
info "Building images with $COMPOSE_CMD..."
$COMPOSE_CMD build

# 5. First-time sign-in
# 5a. Antigravity sign-in
HAS_CREDS=false
if $COMPOSE_CMD run --rm --no-deps -T antigravity-remote \
     test -s /root/.gemini/jetski-standalone-oauth-token >/dev/null 2>&1; then
    success "Existing Antigravity sign-in found in container volume."
    HAS_CREDS=true
elif [[ -t 0 ]]; then
    info "Not signed into Antigravity yet — starting one-time interactive sign-in..."
    $COMPOSE_CMD run --rm antigravity-remote && HAS_CREDS=true || \
        warn "Antigravity sign-in did not complete; you can retry later (see below)."
fi

# 5b. Claude sign-in
HAS_CLAUDE_CREDS=false
if $COMPOSE_CMD run --rm --no-deps -T claude-remote \
     bash -c '[ -s /root/.claude/.credentials.json ] || [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ] || claude auth status >/dev/null 2>&1' >/dev/null 2>&1; then
    success "Existing Claude sign-in found in container volume / environment."
    HAS_CLAUDE_CREDS=true
elif [[ -t 0 ]]; then
    read -r -p "Sign in to Claude Code now? [Y/n] " response || response="y"
    case "$response" in
      [nN][oO]|[nN])
        info "Skipping Claude sign-in for now. You can sign in later."
        ;;
      *)
        info "Starting one-time interactive Claude Code sign-in..."
        $COMPOSE_CMD run --rm claude-remote && HAS_CLAUDE_CREDS=true || \
            warn "Claude sign-in did not complete; you can retry later."
        ;;
    esac
fi

# 6. Launch
info "Starting containers with $COMPOSE_CMD..."
$COMPOSE_CMD up -d

# 7. Next steps
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 Remote Control is up! (Antigravity + Claude) ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo -e "${BOLD}1. Google Antigravity:${NC}"
if [[ "$HAS_CREDS" == "true" ]]; then
  echo -e "   Open ${BLUE}https://antigravity.google.com${NC} to drive Antigravity."
else
  echo -e "   ${YELLOW}Not signed in yet.${NC} Complete sign-in with:"
  echo -e "     ${BLUE}$COMPOSE_CMD run --rm antigravity-remote${NC}"
  echo -e "   then restart: ${BLUE}$COMPOSE_CMD restart antigravity-remote${NC}"
fi
echo ""
echo -e "${BOLD}2. Claude Code:${NC}"
if [[ "$HAS_CLAUDE_CREDS" == "true" ]]; then
  echo -e "   Open ${BLUE}https://claude.ai/code${NC} or the Claude mobile app."
else
  echo -e "   ${YELLOW}Not signed in yet.${NC} Complete sign-in with:"
  echo -e "     ${BLUE}$COMPOSE_CMD run --rm claude-remote${NC}"
  echo -e "   then restart: ${BLUE}$COMPOSE_CMD restart claude-remote${NC}"
fi
echo ""
echo -e "${BOLD}Shared Workspaces:${NC} Both agents share the ${BLUE}/root/dev${NC} volume."
echo ""
echo -e "Logs:"
echo -e "  Antigravity: ${BLUE}$COMPOSE_CMD logs -f antigravity-remote${NC}"
echo -e "  Claude:      ${BLUE}$COMPOSE_CMD logs -f claude-remote${NC}"
echo -e "============================================================"
echo ""
