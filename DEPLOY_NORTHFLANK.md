# Deploying Antigravity-Manager on Northflank

This is a step-by-step guide to deploy Antigravity-Manager (headless backend)
on Northflank's free Sandbox tier.

## Prerequisites

- GitHub account (linked to Northflank)
- Antigravity Pro account (with refresh token)
- An Antigravity API key (any non-empty string you choose)

## Step 1: Prepare the GitHub fork

This fork already has the right Dockerfile (`docker/Dockerfile.backend`).
The compose file `docker-compose.northflank.yml` is configured with
proper port mapping and persistent volume.

If you've changed anything, push:
```bash
git push origin main
```

## Step 2: Deploy on Northflank

1. Log in to [Northflank](https://northflank.com)
2. Open your `tkcaption` project (or create one — "Free" tier)
3. Click **Deploy repository** (or "Create → Service → Deployment")
4. Configure:

| Field | Value |
|---|---|
| Source | `ericx0/Antigravity-Manager-1` (your fork) |
| Branch | `main` |
| Build type | **Dockerfile** |
| Dockerfile path | `docker/Dockerfile.backend` |
| Port | `8045` |
| Health check path | `/health` |
| Region | `US - Central` (or your choice) |

5. Add a **persistent volume**:
   - Mount path: `/root/.antigravity_tools`
   - This is where SQLite + refresh tokens are stored

6. Add environment variables:

| Variable | Value |
|---|---|
| `API_KEY` | (a strong random string — this is what clients must send as Bearer token) |
| `ABV_BIND_LOCAL_ONLY` | `false` |
| `ABV_DATA_DIR` | `/root/.antigravity_tools` |
| `LOG_LEVEL` | `info` |

7. Click **Deploy** — build takes 5-10 minutes (Rust compiles from source)

## Step 3: Get the URL

After deployment, Northflank gives you a URL like:
```
https://tkcaption--antigravity-prod-app.us-central-01.northflank.app
```

Test it:
```bash
curl https://你的域名/health
# → {"status":"ok"} or similar
```

## Step 4: Configure tkcaption

Edit `tkcaption/.env.local`:
```bash
MINIMAX_BASE_URL=https://你的-agm-域名/v1
MINIMAX_MODEL=gemini-2.5-flash
MINIMAX_API_KEY=你刚才设的API_KEY
```

Or in Vercel dashboard → Settings → Environment Variables.

## Step 5: Initial Antigravity account setup

The refresh token for your Antigravity Pro account is normally captured
through the GUI. In headless mode, we need to do it differently:

**Option A: Use the binary's "import" subcommand**
```bash
# Run a one-off shell in the deployed container
docker exec -it antigravity-manager /app/antigravity-tools import-token
# (this command may vary — check the binary's --help)
```

**Option B: Mount the storage.json directly**
1. Get the storage.json from your local Mac Antigravity install:
   ```bash
   cat ~/.antigravity_tools/storage.json
   ```
2. In Northflank, mount a Secret with this JSON content
3. Set `ABV_DATA_DIR_POINTER_FILE` to point to the mounted secret

**Option C: Use the API**
Hit `POST /v1/accounts/add` with the refresh token (check Antigravity's API docs)

## Free tier limits

Northflank Sandbox:
- 2 free services (we use 1 for Antigravity)
- 1 free database
- Always-on (no cold start)
- 2 free cron jobs

That's plenty for a single Antigravity-Manager instance.
