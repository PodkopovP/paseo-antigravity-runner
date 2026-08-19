#!/usr/bin/env bash
# Export Antigravity credentials from this machine in .env format.
#
# Run on the machine where you are logged in to Antigravity (the Antigravity
# app or the `agy` CLI), then append the output to the .env next to
# docker-compose.yml:
#
#   ./scripts/export-credentials.sh >> .env
#
# It exports every credential file it finds so whichever one the standalone
# hub reads is present in the container.
set -u

GEMINI="$HOME/.gemini"
found=false

emit_json() { # var, file
  if [ -f "$2" ]; then
    printf '%s=%s\n' "$1" "$(tr -d '\n' < "$2")"
    found=true
  else
    echo "# $2 not found — skipping $1" >&2
  fi
}

emit_b64() { # var, file
  if [ -f "$2" ]; then
    printf '%s=%s\n' "$1" "$(base64 < "$2" | tr -d '\n')"
    found=true
  else
    echo "# $2 not found — skipping $1" >&2
  fi
}

emit_json OAUTH_CREDS_JSON                "$GEMINI/oauth_creds.json"
emit_json GOOGLE_ACCOUNTS_JSON            "$GEMINI/google_accounts.json"
emit_b64  JETSKI_STANDALONE_OAUTH_TOKEN_B64 "$GEMINI/jetski-standalone-oauth-token"
emit_b64  AGY_OAUTH_TOKEN_B64             "$GEMINI/antigravity-cli/antigravity-oauth-token"

if [ "$found" = false ]; then
  {
    echo ""
    echo "No Antigravity credentials found under ~/.gemini."
    echo "Log in first: open the Antigravity app or run 'agy' once, then re-run."
  } >&2
  exit 1
fi

echo "" >&2
echo "Done. Treat these values as secrets — they grant access to your" >&2
echo "Antigravity account." >&2
