#!/usr/bin/env bash
# scripts/reconstruct-storage.sh
#
# Reconstruct a complete storage.json from Antigravity's split-file layout
# (accounts.json + accounts/<uuid>.json + gui_config.json).
# Use this if you have Antigravity installed locally but no clean export.

set -euo pipefail

AGM_DATA_DIR="${HOME}/.antigravity_tools"
OUTPUT="${1:-$HOME/Desktop/antigravity_storage.json}"

if [[ ! -d "$AGM_DATA_DIR" ]]; then
  echo "ERROR: $AGM_DATA_DIR not found. Is Antigravity-Manager installed?" >&2
  exit 1
fi

if [[ ! -f "$AGM_DATA_DIR/accounts.json" ]]; then
  echo "ERROR: $AGM_DATA_DIR/accounts.json not found." >&2
  exit 1
fi

# Load accounts metadata
ACCOUNTS_JSON=$(cat "$AGM_DATA_DIR/accounts.json")
CURRENT_ID=$(echo "$ACCOUNTS_JSON" | jq -r '.current_account_id // empty')
if [[ -z "$CURRENT_ID" ]]; then
  echo "WARN: no current_account_id, using first account."
  CURRENT_ID=$(echo "$ACCOUNTS_JSON" | jq -r '.accounts[0].id // empty')
fi

if [[ -z "$CURRENT_ID" ]]; then
  echo "ERROR: no accounts found." >&2
  exit 1
fi

ACCT_FILE="$AGM_DATA_DIR/accounts/$CURRENT_ID.json"
if [[ ! -f "$ACCT_FILE" ]]; then
  echo "ERROR: $ACCT_FILE not found." >&2
  exit 1
fi

# Build the unified storage.json
ACCOUNT_DATA=$(cat "$ACCT_FILE")
GUI_CONFIG=$(cat "$AGM_DATA_DIR/gui_config.json" 2>/dev/null || echo "null")

jq -n \
  --argjson meta "$ACCOUNTS_JSON" \
  --argjson account "$ACCOUNT_DATA" \
  --argjson gui "$GUI_CONFIG" \
  '{
    version: $meta.version,
    accounts: $meta.accounts,
    current_account_id: $meta.current_account_id,
    current_target_ide: $meta.current_target_ide,
    account_details: {($account.id): $account},
    gui_config: $gui
  }' > "$OUTPUT"

echo "Wrote: $OUTPUT"
echo "Account: $(echo "$ACCOUNT_DATA" | jq -r '.email')"
echo "Tier: $(echo "$ACCOUNT_DATA" | jq -r '.quota.subscription_tier')"
echo "Refresh token length: $(echo "$ACCOUNT_DATA" | jq -r '.token.refresh_token | length')"
