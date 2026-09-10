#!/bin/zsh
# Starts the self-hosted Rakazo production stack on the Mac Studio + Caddy front door.
# Canonical URL: https://rakazo.czaku.com (Caddy launch agent com.rakazo.caddy, LE cert via Cloudflare DNS-01)
# No Vite process at all: web is a static build (`pnpm --filter @rakazo/web build` -> apps/web/dist)
# served directly by Caddy (see ops/Caddyfile.rakazo-block). api/worker/sandbox-supervisor run via
# their `start` scripts (tsx, no watch) as launchd KeepAlive agents (ops/launchd/*.plist) instead of
# a single nohup'd `pnpm dev`. This script rebuilds the web bundle, (re)starts Postgres, and
# kickstarts the launchd agents.
set -e
PORT=31415  # Caddy TLS port; tailscaled forwards :443 -> 127.0.0.1:31415 (tailscale serve --tcp=443), so URLs carry no port
if lsof -nP -iTCP:$PORT -sTCP:LISTEN | grep -v caddy >/dev/null 2>&1; then echo "PORT $PORT is held by another process:"; lsof -nP -iTCP:$PORT -sTCP:LISTEN; exit 1; fi
cd "$HOME/dev/rakazo-setup/rakazo"
mkdir -p "$HOME/dev/rakazo-setup/.logs"
docker compose --env-file .env -f infra/compose/docker-compose.yml \
  -f infra/compose/docker-compose.postgres-host.local.yml up postgres -d

pnpm --filter @rakazo/web build

for agent in com.rakazo.api com.rakazo.worker com.rakazo.sandbox-supervisor; do
  launchctl kickstart -k "gui/$(id -u)/$agent" 2>/dev/null \
    || launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist"
done

tailscale serve --bg --tcp=443 tcp://127.0.0.1:31415
launchctl kickstart "gui/$(id -u)/com.rakazo.caddy" 2>/dev/null \
  || launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.rakazo.caddy.plist
echo "api:   http://127.0.0.1:3100/health"
echo "phone: https://rakazo.czaku.com  (Tailscale on)"
