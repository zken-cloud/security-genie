#!/usr/bin/env bash
# set-iap-oauth-client.sh — point IAP at a CUSTOM OAuth client.
#
# IAP on a custom domain must use your own OAuth client. With the Google-managed
# client, sign-in dies at
#   https://<domain>/?gcp-iap-mode=AUTHENTICATING&redirect_token_v2=...
#   "There was a problem with your request ... Error code 11"
# Every other layer looks healthy, so this only shows up in a real browser.
#
# Create the client first (Console — see site/README.md), then:
#   ./site/set-iap-oauth-client.sh <CLIENT_ID>              # prompts, no echo
#   ./site/set-iap-oauth-client.sh <CLIENT_ID> <SECRET_FILE> # reads from a file
#
# Either way the secret never lands in the transcript or your shell history. The
# file form exists so an agent can run this step for you: you write the secret to
# a file, the script consumes and shreds it. Never pass the secret as an
# argument — arguments are visible in the process list.
#
# Note: `gcloud iap oauth-clients describe` no longer returns the secret (that
# part of the OAuth Admin API is turned down), so it cannot be fetched for you.
set -euo pipefail

PROJECT="${PROJECT:?set PROJECT (GCP project that owns the backend service)}"
BACKEND="${BACKEND:-security-genie-backend}"
CLIENT_ID="${1:-}"
SECRET_FILE="${2:-}"

if [[ -z "$CLIENT_ID" ]]; then
  echo "usage: $0 <OAUTH_CLIENT_ID> [SECRET_FILE]" >&2
  exit 1
fi

if [[ -n "$SECRET_FILE" ]]; then
  [[ -r "$SECRET_FILE" ]] || { echo "cannot read $SECRET_FILE" >&2; exit 1; }
  CLIENT_SECRET="$(tr -d '\r\n' < "$SECRET_FILE")"
  shred -u "$SECRET_FILE" 2>/dev/null || rm -f "$SECRET_FILE"
  echo "Read secret from $SECRET_FILE (${#CLIENT_SECRET} chars, not shown); file removed."
else
  read -rsp "OAuth client secret for ${CLIENT_ID}: " CLIENT_SECRET; echo
fi
[[ -n "$CLIENT_SECRET" ]] || { echo "empty secret, aborting" >&2; exit 1; }

gcloud compute backend-services update "$BACKEND" --global --project="$PROJECT" \
  --iap="enabled,oauth2-client-id=${CLIENT_ID},oauth2-client-secret=${CLIENT_SECRET}"

unset CLIENT_SECRET

echo
echo "Configured. Verify:"
gcloud compute backend-services describe "$BACKEND" --global --project="$PROJECT" \
  --format='value(iap.enabled,iap.oauth2ClientId)'
echo
echo "Now sign in from a browser as an account in the IAP-granted domain. Command-line checks"
echo "cannot catch Error code 11 — only a completed OAuth flow can."
