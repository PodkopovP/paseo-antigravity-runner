#!/usr/bin/env bash
# ==============================================================================
# Paseo + Antigravity Runner — One-Line Installer & Updater
# ==============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/PodkopovP/paseo-antigravity-runner/main/setup.sh | bash
#   OR
#   ./setup.sh
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

fatal() {
    error "$1"
    exit 1
}

echo -e "${BOLD}"
echo "============================================================"
echo "  🚀 Paseo + Antigravity Runner Setup & Update Tool"
echo "============================================================"
echo -e "${NC}"

# 1. Pre-flight checks ("Fool-proof" verification)

info "Checking system prerequisites..."

# Check Docker installation
if ! command -v docker >/dev/null 2>&1; then
    fatal "Docker is not installed! Please install Docker first: https://docs.docker.com/get-docker/"
fi

# Check Docker daemon availability
if ! docker info >/dev/null 2>&1; then
    fatal "Docker daemon is not running or your user does not have permissions to access Docker.\nPlease start Docker or ensure your user is in the 'docker' group (or run with sudo)."
fi

# Check Docker Compose (support V2 plugin 'docker compose' or V1 binary 'docker-compose')
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    fatal "Docker Compose is not installed! Please install Docker Compose (v2 recommended): https://docs.docker.com/compose/install/"
fi

# Check git
if ! command -v git >/dev/null 2>&1; then
    fatal "Git is not installed! Please install Git to proceed."
fi

success "Prerequisites check passed (using '$COMPOSE_CMD')."

# 2. Repository directory management

REPO_NAME="paseo-antigravity-runner"
REPO_URL="https://github.com/PodkopovP/paseo-antigravity-runner.git"

# Determine if we are currently inside the repo directory
if [[ -f "docker-compose.yml" && -f "Dockerfile" ]]; then
    info "Running inside repository directory '$(pwd)'."
    if [[ -d ".git" ]]; then
        info "Updating repository code..."
        git pull --rebase || warn "git pull failed; continuing with existing files."
    fi
elif [[ -d "$REPO_NAME" && -f "$REPO_NAME/docker-compose.yml" ]]; then
    info "Found directory '$REPO_NAME'. Entering..."
    cd "$REPO_NAME"
    if [[ -d ".git" ]]; then
        info "Updating repository code..."
        git pull --rebase || warn "git pull failed; continuing with existing files."
    fi
else
    info "Cloning repository from $REPO_URL..."
    git clone "$REPO_URL" "$REPO_NAME"
    cd "$REPO_NAME"
fi

# 3. Environment & Credential Setup

if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        info "Creating .env configuration file from .env.example..."
        cp .env.example .env
    else
        fatal ".env.example not found! Repository file structure may be corrupted."
    fi
fi

# Check if credentials exist in .env
HAS_CREDS=false
if grep -qE '^AGY_OAUTH_TOKEN_B64=[^[:space:]]+' .env 2>/dev/null || grep -qE '^OAUTH_CREDS_JSON=[^[:space:]]+' .env 2>/dev/null; then
    HAS_CREDS=true
fi

if [[ "$HAS_CREDS" == "false" ]]; then
    info "No Antigravity credentials found in .env. Checking for local Antigravity login..."
    
    TOKEN_FILE="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    CREDS_FILE="$HOME/.gemini/oauth_creds.json"
    
    if [[ -f "$TOKEN_FILE" || -f "$CREDS_FILE" ]]; then
        info "Found local Antigravity credentials! Exporting to .env..."
        if [[ -x "./scripts/export-credentials.sh" ]]; then
            ./scripts/export-credentials.sh >> .env
            HAS_CREDS=true
            success "Local Antigravity credentials auto-exported into .env."
        else
            bash ./scripts/export-credentials.sh >> .env
            HAS_CREDS=true
            success "Local Antigravity credentials auto-exported into .env."
        fi
    else
        warn "------------------------------------------------------------"
        warn "NO ANTIGRAVITY CREDENTIALS DETECTED!"
        warn "The runner will start, but Antigravity will be unavailable until auth is configured."
        warn "To add credentials:"
        warn "  1. On a machine logged in to Antigravity, run:"
        warn "     ./scripts/export-credentials.sh >> .env"
        warn "  2. Restart the runner with: $COMPOSE_CMD restart"
        warn "------------------------------------------------------------"
    fi
else
    success "Antigravity credentials found in .env."
fi

# 4. Container Build & Launch

info "Building and starting container with $COMPOSE_CMD..."
$COMPOSE_CMD up -d --build

# 5. Success & Pairing Guide

echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD} 🎉 Paseo Antigravity Runner is up and running! ${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo -e "${BOLD}Next Step: Pair your device${NC}"
echo -e "Run the following command to print the QR code / pairing link:"
echo ""
echo -e "   ${BLUE}${BOLD}$COMPOSE_CMD exec paseo paseo-pair${NC}"
echo ""
echo -e "Open the Paseo app (https://app.paseo.sh or mobile app) and scan the QR code."
echo -e "============================================================"
echo ""
