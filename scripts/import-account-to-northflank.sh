#!/usr/bin/env bash
# scripts/import-account-to-northflank.sh
#
# Push a local Antigravity Pro account (refresh token) to a Northflank-deployed
# Antigravity-Manager service. The remote service then uses your Antigravity Pro
# subscription for LLM calls.
#
# Usage:
#   ./import-account-to-northflank.sh /path/to/storage.json

set -euo pipefail

# ---- Configuration ----
NORTHFLANK_PROJECT_ID="tkcaption"
NORTHFLANK_SERVICE_ID="tkcaption"
REMOTE_DIR="/root/.antigravity_tools"
REMOTE_FILE="${REMOTE_DIR}/storage.json"

STORAGE_FILE="${1:-}"

# ---- Preflight ----
echo "==> Import Antigravity Pro account to Northflank service"
echo ""

if [[ -z "$STORAGE_FILE" || ! -f "$STORAGE_FILE" ]]; then
  echo "ERROR: Pass the path to your storage.json" >&2
  echo "" >&2
  echo "  Tip: export from Antigravity-Manager GUI, or rebuild from local" >&2
  echo "       ~/.antigravity_tools/accounts.json + accounts/<uuid>.json" >&2
  echo "" >&2
  echo "Usage: $0 /path/to/storage.json" >&2
  exit 1
fi

if ! command -v northflank >/dev/null 2>&1; then
  echo "ERROR: Northflank CLI not installed" >&2
  echo "Install: brew install northflank/tap/northflank" >&2
  exit 1
fi

# Sanity-check JSON
if ! jq -e . "$STORAGE_FILE" >/dev/null 2>&1; then
  echo "ERROR: $STORAGE_FILE is not valid JSON" >&2
  exit 1
fi

FILE_SIZE=$(stat -f%z "$STORAGE_FILE" 2>/dev/null || stat -c%s "$STORAGE_FILE")
echo "Storage file: $STORAGE_FILE ($FILE_SIZE bytes)"

# Show what account is being uploaded (no secrets)
if command -v jq >/dev/null 2>&1; then
  PRIMARY=$(jq -r '.current_account_id // .accounts[0].id // "?"' "$STORAGE_FILE")
  EMAIL=$(jq -r ".account_details["$PRIMARY"].email // .accounts[0].email // "?"" "$STORAGE_FILE" 2>/dev/null)
  TIER=$(jq -r ".account_details["$PRIMARY"].quota.subscription_tier // "unknown"" "$STORAGE_FILE" 2>/dev/null)
  MODELS=$(jq -r ".account_details["$PRIMARY"].quota.models | length // 0" "$STORAGE_FILE" 2>/dev/null)
  echo "Account:  $EMAIL"
  echo "Tier:     $TIER"
  echo "Models:   $MODELS"
fi

echo ""
echo "Upload target:"
echo "  project: $NORTHFLANK_PROJECT_ID"
echo "  service: $NORTHFLANK_SERVICE_ID"
echo "  remote:  $REMOTE_FILE"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 1
fi

# ---- Ensure remote directory exists ----
echo ""
echo "==> Ensuring remote directory exists..."
northflank exec service \
  --projectId "$NORTHFLANK_PROJECT_ID" \
  --serviceId "$NORTHFLANK_SERVICE_ID" \
  -- bash -c "mkdir -p $REMOTE_DIR" || true

# ---- Upload file ----
echo ""
echo "==> Uploading storage.json to volume..."
if ! northflank upload service file \
    --projectId "$NORTHFLANK_PROJECT_ID" \
    --serviceId "$NORTHFLANK_SERVICE_ID" \
    --localPath "$STORAGE_FILE" \
    --remotePath "$REMOTE_FILE" 2>&1; then
  echo "ERROR: upload failed" >&2
  exit 1
fi

# ---- Restart service ----
echo ""
echo "==> Restarting service to pick up the new token..."
if ! northflank restart service \
    --projectId "$NORTHFLANK_PROJECT_ID" \
    --serviceId "$NORTHFLANK_SERVICE_ID" 2>&1; then
  echo "WARN: restart failed; please restart manually from the Northflank dashboard."
fi

# ---- Verify ----
echo ""
echo "==> Verifying (waiting for service to come back online)..."
sleep 8

PUBLIC_URL=$(northflank get service \
    --projectId "$NORTHFLANK_PROJECT_ID" \
    --serviceId "$NORTHFLANK_SERVICE_ID" 2>/dev/null | \
    grep -oE "https://[a-z0-9-]+\.code\.run" | head -1)

if [[ -z "$PUBLIC_URL" ]]; then
  echo "WARN: could not auto-detect public URL. Get it from the Northflank dashboard manually."
  echo "Done."
  exit 0
fi

echo "Public URL: $PUBLIC_URL"
echo ""
echo "Testing /v1/models..."

if [[ -n "${AGM_API_KEY:-}" ]]; then
  API_KEY="$AGM_API_KEY"
else
  echo "Enter the API_KEY you set in the service environment (or press Enter to skip test):"
  read -s -r API_KEY
  echo ""
fi

if [[ -n "$API_KEY" ]]; then
  RESP=$(curl -s -H "Authorization: Bearer $API_KEY" "$PUBLIC_URL/v1/models" 2>&1 || true)
  if echo "$RESP" | grep -q '"data"'; then
    MODEL_COUNT=$(echo "$RESP" | jq '.data | length' 2>/dev/null || echo "?")
    echo ""
    echo "SUCCESS! /v1/models returned $MODEL_COUNT models."
    echo "Antigravity Pro account is now active on the remote service."
    echo ""
    echo "Next: point tkcaption at this URL by setting in .env.local:"
    echo "  MINIMAX_BASE_URL=$PUBLIC_URL/v1"
    echo "  MINIMAX_MODEL=gemini-2.5-flash"
    echo "  MINIMAX_API_KEY=$API_KEY"
  else
    echo ""
    echo "WARN: /v1/models did not return a model list."
    echo "Response: $RESP"
  fi
fi

echo ""
echo "==> Done!"
