#!/usr/bin/env bash
# scripts/import-token-to-northflank.sh
# 
# Push local Antigravity storage.json (refresh tokens) from your Mac
# to the Antigravity service running on Northflank.
#
# Prerequisites:
#   1. Antigravity-Manager is installed locally with Antigravity Pro account logged in
#      (storage.json exists at ~/.antigravity_tools/storage.json)
#   2. Northflank CLI is installed and logged in:
#      brew install northflank/tap/northflank
#      northflank login
#   3. Antigravity service deployed on Northflank (tkcaption project)
#
# Usage:
#   ./import-token-to-northflank.sh

set -euo pipefail

# ---- Configuration ----
NORTHFLANK_PROJECT_ID="tkcaption"
NORTHFLANK_SERVICE_ID="tkcaption"
ANTIGRAVITY_DATA_DIR="${HOME}/.antigravity_tools"
STORAGE_FILE="${ANTIGRAVITY_DATA_DIR}/storage.json"
REMOTE_PATH="/root/.antigravity_tools/storage.json"

# ---- Preflight ----
echo "==> Antigravity token import to Northflank"
echo ""

# 1. Check local storage.json exists
if [[ ! -f "$STORAGE_FILE" ]]; then
  echo "ERROR: Local storage.json not found at: $STORAGE_FILE" >&2
  echo "       Make sure Antigravity-Manager is installed and you logged in to your Antigravity Pro account." >&2
  exit 1
fi

# 2. Show what we are about to send (no secrets)
FILE_SIZE=$(stat -f%z "$STORAGE_FILE" 2>/dev/null || stat -c%s "$STORAGE_FILE")
echo "Local storage.json:"
echo "  path: $STORAGE_FILE"
echo "  size: $FILE_SIZE bytes"

# 3. Basic validation: parse JSON and confirm it has at least one account with a refresh_token
if ! command -v jq >/dev/null 2>&1; then
  echo "WARN: jq not installed, skipping JSON validation"
else
  echo ""
  echo "Validating storage.json structure..."
  if ! jq -e '.accounts | type == "array" and length > 0' "$STORAGE_FILE" >/dev/null 2>&1; then
    # Try legacy / single-account shape
    if ! jq -e '.account or .refresh_token' "$STORAGE_FILE" >/dev/null 2>&1; then
      echo "ERROR: storage.json does not look like an Antigravity account file." >&2
      echo "       Expected an `accounts` array or top-level `account` / `refresh_token` field." >&2
      exit 1
    fi
  fi
  ACCT_COUNT=$(jq -r '.accounts | if type == "array" then length else 0 end' "$STORAGE_FILE" 2>/dev/null || echo "?")
  EMAIL=$(jq -r '.accounts[0].email // .account.email // "unknown"' "$STORAGE_FILE" 2>/dev/null || echo "?")
  echo "  accounts found: $ACCT_COUNT"
  echo "  primary account: $EMAIL"
fi

echo ""
echo "About to upload to:"
echo "  project: $NORTHFLANK_PROJECT_ID"
echo "  service: $NORTHFLANK_SERVICE_ID"
echo "  remote path: $REMOTE_PATH"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 1
fi

# ---- Upload ----
echo ""
echo "==> Uploading storage.json..."
if ! northflank upload service file     --projectId "$NORTHFLANK_PROJECT_ID"     --serviceId "$NORTHFLANK_SERVICE_ID"     --localPath "$STORAGE_FILE"     --remotePath "$REMOTE_PATH" 2>&1; then
  echo "ERROR: upload failed" >&2
  echo "" >&2
  echo "Troubleshooting:" >&2
  echo "  1. Make sure 'northflank login' was run" >&2
  echo "  2. Verify project/service IDs: northflank get service --projectId $NORTHFLANK_PROJECT_ID" >&2
  echo "  3. Check the volume 'agmdata' is attached to this service" >&2
  exit 1
fi

echo "Upload complete."

# ---- Restart service to pick up the new file ----
echo ""
echo "==> Restarting service to pick up the new storage.json..."
if ! northflank restart service     --projectId "$NORTHFLANK_PROJECT_ID"     --serviceId "$NORTHFLANK_SERVICE_ID" 2>&1; then
  echo "WARN: restart command failed. You may need to restart manually via the Northflank dashboard."
fi

# ---- Verify ----
echo ""
echo "==> Verification (waiting for service to come back online)..."
sleep 5

# Get public URL from service details
PUBLIC_URL=$(northflank get service     --projectId "$NORTHFLANK_PROJECT_ID"     --serviceId "$NORTHFLANK_SERVICE_ID" 2>/dev/null |     grep -oE "https://[a-z0-9-]+\.code\.run" | head -1)

if [[ -z "$PUBLIC_URL" ]]; then
  echo "WARN: could not auto-detect public URL. Get it from the Northflank dashboard manually."
  echo "Done."
  exit 0
fi

echo "Public URL: $PUBLIC_URL"
echo ""
echo "Testing /v1/models..."

# Read the API_KEY from environment variable if set, otherwise prompt
if [[ -n "${AGM_API_KEY:-}" ]]; then
  API_KEY="$AGM_API_KEY"
else
  echo "Enter the API_KEY you set in the service environment (or press Enter to skip test):"
  read -s -r API_KEY
  echo ""
fi

if [[ -n "$API_KEY" ]]; then
  RESP=$(curl -s -H "Authorization: Bearer $API_KEY" "$PUBLIC_URL/v1/models" 2>&1 || true)
  if echo "$RESP" | grep -q "data"; then
    echo "OK! /v1/models returned a model list:"
    echo "$RESP" | head -c 500
    echo ""
    echo ""
    echo "Antigravity Pro account is now active on the remote service."
  else
    echo "WARN: /v1/models did not return a model list."
    echo "Response: $RESP"
    echo ""
    echo "Possible issues:"
    echo "  - The API_KEY in the remote service doesn't match (check Northflank env vars)"
    echo "  - The refresh token is invalid (try logging in again locally)"
    echo "  - Antigravity Pro subscription expired"
  fi
else
  echo "Skipped verification (no API_KEY provided)."
fi

echo ""
echo "==> Done!"
