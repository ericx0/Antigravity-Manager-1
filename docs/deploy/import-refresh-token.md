# Importing Antigravity Pro Refresh Token to Northflank

When you run Antigravity-Manager headless (e.g. on Northflank), the local
GUI account you logged in to doesn't transfer automatically — the headless
container starts with an empty `storage.json`.

This guide shows you how to import your Antigravity Pro account from your
local Mac to the remote Northflank-deployed service.

## Prerequisites

- [Antigravity-Manager](https://github.com/lbjlaq/Antigravity-Manager) installed and running locally
- Logged in to your Antigravity Pro account via the local GUI
- `~/.antigravity_tools/storage.json` exists (this is your token storage)
- Antigravity service deployed on Northflank (this guide assumes `tkcaption` project)
- [Northflank CLI](https://docs.northflank.com/cli/installation) installed and logged in
- Your Antigravity service has a persistent volume mounted at `/root/.antigravity_tools` (called `agmdata` in this guide)

## Step 1: Run the import script

```bash
git clone https://github.com/ericx0/Antigravity-Manager-1.git
cd Antigravity-Manager-1
chmod +x scripts/import-token-to-northflank.sh
./scripts/import-token-to-northflank.sh
```

The script will:

1. Verify `~/.antigravity_tools/storage.json` exists locally
2. Validate JSON structure (must have an `accounts` array with at least one entry)
3. Show you the primary account email (so you can confirm you're sending the right one)
4. Ask for confirmation
5. Upload via `northflank upload service file`
6. Restart the service to pick up the new file
7. Test the deployment via `/v1/models`

## Step 2: Verify the deployment

The script will print a test like:

```
Public URL: https://p02--tkcaption-h224zrcqz9gk.code.run
Testing /v1/models...

OK! /v1/models returned a model list:
{"object":"list","data":[{"id":"gemini-2.5-pro",...}]}

==> Done!
```

If `/v1/models` returns a list, your Antigravity Pro account is now active
on the Northflank-deployed service. The remote service will:
- Use your Antigravity Pro model quota
- Refresh access tokens automatically
- Load balance across your Antigravity Pro accounts (if you have multiple)

## Step 3: Point tkcaption at the remote service

Edit `tkcaption/.env.local`:

```bash
MINIMAX_BASE_URL=https://p02--tkaption-h224zrcqz9gk.code.run/v1
MINIMAX_MODEL=gemini-2.5-flash
MINIMAX_API_KEY=你之前设的强密码
```

The `MINIMAX_API_KEY` here is the API_KEY env var you set on the Northflank
service (used by tkcaption to authenticate against Antigravity's proxy). It's
NOT your Antigravity Pro account credentials.

## Token rotation

If your Antigravity Pro refresh token expires or you want to add another
account, just:

1. Log in / add the account locally via Antigravity-Manager's GUI
2. Re-run the import script — it overwrites the remote `storage.json`

The remote service will pick up the new token on next restart (or use
the cached token until it expires).

## Security

- The script uses HTTPS / Northflank CLI for upload (encrypted in transit)
- Northflank volumes are encrypted at rest
- The refresh token never leaves your machine in plaintext
- Only the person with Northflank dashboard access can see / dump the token

If you ever suspect compromise, rotate your Antigravity Pro account
credentials in the Antigravity web admin and re-run the script.
