#!/usr/bin/env bash
# Export Antigravity credentials from this machine in .env format.
#
# Run on the machine where you are logged in to Antigravity (the IDE or the
# `agy` CLI), then paste the output into the .env file next to
# docker-compose.yml — or redirect it there directly:
#
#   ./scripts/export-credentials.sh >> .env
#
set -u

TOKEN_FILE="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
CREDS_FILE="$HOME/.gemini/oauth_creds.json"

found=false

if [ -f "$TOKEN_FILE" ]; then
  token_b64=$(base64 < "$TOKEN_FILE" | tr -d '\n')
  echo "AGY_OAUTH_TOKEN_B64=$token_b64"
  found=true
else
  echo "# $TOKEN_FILE not found — skipping AGY_OAUTH_TOKEN_B64" >&2
fi

if [ -f "$CREDS_FILE" ]; then
  creds=$(tr -d '\n' < "$CREDS_FILE")
  echo "OAUTH_CREDS_JSON=$creds"
  found=true
else
  echo "# $CREDS_FILE not found — skipping OAUTH_CREDS_JSON" >&2
fi

if [ "$found" = false ]; then
  echo "" >&2
  echo "No Antigravity credentials found under ~/.gemini." >&2
  echo "Log in first: install Antigravity and run 'agy' once, or sign in" >&2
  echo "through the Antigravity IDE, then re-run this script." >&2
  exit 1
fi

echo "" >&2
echo "Done. Treat these values as secrets — they grant access to your" >&2
echo "Antigravity account." >&2
