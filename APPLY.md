# APPLY.md — T-RKZ-002 live cutover steps (run these yourself on the Mac Studio)

Everything below is ops on the live machine (`~/dev/rakazo-setup`), which this lane's worktree
cannot write to (cwd-guard) and which the task brief keeps outside git anyway. This lane already
did the reversible, in-repo part: killed the old `pnpm dev` stack by exact pid and replaced it with
a temporary `nohup` bridge (api/worker/sandbox-supervisor via `start`, web via `vite preview`) using
the **existing, unmodified `.env`**, so the site is live right now on the fixed processes. Verified:
`/health` OK (direct), root page 200, old dev pids confirmed dead (see the commit history for the
pids).

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

## 1. Web serving — static build for everything, `vite preview` kept alive only for /novnc

```bash
cd ~/dev/rakazo-setup/rakazo
pnpm --filter @rakazo/web build   # produces apps/web/dist
```

Caddy serves `apps/web/dist` directly (`root * ... ; file_server` + SPA fallback) for every route
except `/novnc/*`, and reverse-proxies `/api`, `/rpc`, `/health` to the API at 127.0.0.1:3100.
`/novnc/*` alone is routed to `pnpm --filter @rakazo/web preview` on 127.0.0.1:5173, launchd-managed
via `com.rakazo.web.plist` — the actual noVNC byte-proxying logic
(`resolveNovncTarget`/`safeProxyHeaders`/`watchScreenAuthorization` in
`apps/web/src/screen-proxy.ts`) only runs inside Vite's own Node process, and `apps/api` has no
`/novnc` route of its own, so this keeps bot screen viewing working without porting that logic.
Rerun the build (`ops/start-rakazo.sh` does this automatically) any time the web app changes — the
static dist directory is what's actually deployed; the `preview` process's own copy of `dist` only
matters for `/novnc` and is not otherwise in the request path.

`/events` was in the original task text but does not exist anywhere in this codebase (grepped
`apps/api/src` and `apps/web/src` for `/events`, `text/event-stream`, `EventSource` — no hits;
realtime is Postgres-backed over `/rpc`), so no Caddy handler is defined for it.

## 2. Caddyfile

Replace the `rakazo.czaku.com { ... }` block in `~/dev/rakazo-setup/caddy/Caddyfile` with the
contents of `ops/Caddyfile.rakazo-block` in this worktree. Then:

```
launchctl kickstart -k gui/$(id -u)/com.rakazo.caddy
```

## 3. `.env` — production mode + DATA_DIR outside the repo

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

## 4. launchd agents (api, worker, sandbox-supervisor, web)

```bash
cp ~/dev/rakazo-setup/rakazo/.worktrees/lane-T-RKZ-002/ops/launchd/com.rakazo.*.plist \
   ~/Library/LaunchAgents/
mkdir -p ~/dev/rakazo-setup/.logs
```

## 5. Cut over

```bash
# Stop this lane's temporary bridge processes (pids printed in this session's git history:
# api=62324 worker=62325 sandbox-supervisor=62326 web=62327).
# If the session/machine has restarted since, re-find them instead of trusting these pids:
#   pgrep -fl "start$|vite preview"
kill 62324 62325 62326 62327

cp ~/dev/rakazo-setup/rakazo/.worktrees/lane-T-RKZ-002/ops/start-rakazo.sh ~/dev/rakazo-setup/start-rakazo.sh
chmod +x ~/dev/rakazo-setup/start-rakazo.sh
~/dev/rakazo-setup/start-rakazo.sh
```

## 6. Verify

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://rakazo.czaku.com/@fs/pnpm-lock.yaml   # want 404
curl -s -o /dev/null -w '%{http_code}\n' https://rakazo.czaku.com/health                # want 200
launchctl list | grep com.rakazo                                                        # want 4 agents + caddy, all running
```
Then: log in from the MacBook browser and the iPhone app, run one bot to completion, and open its
screen view to confirm `/novnc` still works through the new routing. This lane could not test the
phone app, a live bot run, or noVNC itself.

## 7. INSTALL-LOG.md

Append a short entry noting the cutover date, the `.env`/Caddyfile/launchd changes above, and the
`BETTER_AUTH_URL`/`API_URL` fix from step 0.
