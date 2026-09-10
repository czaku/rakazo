# APPLY.md — T-RKZ-002 live cutover steps (run these yourself on the Mac Studio)

Everything below is ops on the live machine (`~/dev/rakazo-setup`), which this lane's worktree
cannot write to (cwd-guard) and which the task brief keeps outside git anyway. This lane already
did the reversible, in-repo part: killed the old `pnpm dev` stack by exact pid and replaced it with
a temporary `nohup` production-style stack (`start`/`preview` instead of `dev`/watch) using the
**existing, unmodified `.env`**, so the site is live right now on the fixed processes. Verified:
`/health` OK, root page 200, old dev pids confirmed dead (see PROOF below). `/@fs/...` currently
still 200s (SPA fallback) and `/health` isn't actually proxied by Caddy today — both are Caddyfile
fixes below, not code.

## 0. Bug found while verifying — fix first

`.env` has a real mismatch: `WEB_ORIGIN=https://rakazo.czaku.com` but `BETTER_AUTH_URL` and
`API_URL` still point at `https://mac-studio.taild8155a.ts.net:8444` (the old tailscale-only URL
from initial install). `packages/auth/src/index.ts` uses `BETTER_AUTH_URL` as Better Auth's
`baseURL` — likely why login/session behavior over the real domain is degraded today, independent
of the dev-server issue this task was filed for. Fix:

```env
BETTER_AUTH_URL=https://rakazo.czaku.com
API_URL=https://rakazo.czaku.com
```

## 1. Caddyfile

Replace the `rakazo.czaku.com { ... }` block in `~/dev/rakazo-setup/caddy/Caddyfile` with the
contents of `ops/Caddyfile.rakazo-block` in this worktree (adds explicit `/health` proxy and an
explicit `/@fs/*` 404 — see comments in that file for why both are needed). Then:

```
launchctl kickstart -k gui/$(id -u)/com.rakazo.caddy
```

## 2. `.env` — production mode + DATA_DIR outside the repo

```env
NODE_ENV=production
DATA_DIR=/Users/luke/Library/Application Support/rakazo/data
```

Migrate the existing data (stop-safe — API/worker only read `DATA_DIR` at process start, so do
this right before the launchd bootstrap in step 4, while api/worker are down):

```bash
mkdir -p "/Users/luke/Library/Application Support/rakazo"
rsync -a ~/dev/rakazo-setup/rakazo/data/ "/Users/luke/Library/Application Support/rakazo/data/"
```

Do not delete `~/dev/rakazo-setup/rakazo/data` until you've confirmed a bot run completes against
the new location.

## 3. launchd agents

```bash
cp ~/dev/rakazo-setup/rakazo/.worktrees/lane-T-RKZ-002/ops/launchd/com.rakazo.*.plist \
   ~/Library/LaunchAgents/
```

## 4. Cut over

```bash
# Stop this lane's temporary bridge processes (started 2026-09-10, this session):
#   api=62324 worker=62325 sandbox-supervisor=62326 web=62327
# If the session/machine has restarted since, re-find them instead of trusting these pids:
#   pgrep -fl "start$|vite preview"
kill 62324 62325 62326 62327

# Then bring up the permanent launchd-managed stack
cp ~/dev/rakazo-setup/rakazo/.worktrees/lane-T-RKZ-002/ops/start-rakazo.sh ~/dev/rakazo-setup/start-rakazo.sh
chmod +x ~/dev/rakazo-setup/start-rakazo.sh
~/dev/rakazo-setup/start-rakazo.sh
```

## 5. Verify

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://rakazo.czaku.com/@fs/pnpm-lock.yaml   # want 404
curl -s -o /dev/null -w '%{http_code}\n' https://rakazo.czaku.com/health                # want 200
launchctl list | grep com.rakazo                                                        # want 4 agents, all running
```
Then: log in from the MacBook browser and the iPhone app, and run one bot to completion. This lane
could not test the phone app or a live bot run itself.

## 6. INSTALL-LOG.md

Append a short entry noting the cutover date, the `.env`/Caddyfile/launchd changes above, and the
`BETTER_AUTH_URL`/`API_URL` fix from step 0.
