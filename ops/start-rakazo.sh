#!/bin/zsh
# Starts the self-hosted Rakazo production stack on the Mac Studio + Caddy front door.
# Canonical URL: https://rakazo.czaku.com (Caddy launch agent com.rakazo.caddy, LE cert via Cloudflare DNS-01)
# No Vite dev server: web is served via `vite preview` (built dist/, no /@fs), api/worker/
# sandbox-supervisor run via their `start` scripts (tsx, no watch). All four run as launchd
# KeepAlive agents (see ops/launchd/*.plist in the rakazo repo) instead of a single nohup'd
# `pnpm dev` — this script now just (re)starts Postgres and kickstarts the launchd agents.
set -e
PORT=31415  # Caddy TLS port; tailscaled forwards :443 -> 127.0.0.1:31415 (tailscale serve --tcp=443), so URLs carry no port
if lsof -nP -iTCP:$PORT -sTCP:LISTEN | grep -v caddy >/dev/null 2>&1; then echo "PORT $PORT is held by another process:"; lsof -nP -iTCP:$PORT -sTCP:LISTEN; exit 1; fi
cd "$HOME/dev/rakazo-setup/rakazo"
mkdir -p .logs
docker compose --env-file .env -f infra/compose/docker-compose.yml \
  -f infra/compose/docker-compose.postgres-host.local.yml up postgres -d

for agent in com.rakazo.api com.rakazo.worker com.rakazo.sandbox-supervisor com.rakazo.web; do
  launchctl kickstart -k "gui/$(id -u)/$agent" 2>/dev/null \
    || launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist"
done

tailscale serve --bg --https=8444 http://127.0.0.1:5173
tailscale serve --bg --tcp=443 tcp://127.0.0.1:31415
launchctl kickstart "gui/$(id -u)/com.rakazo.caddy" 2>/dev/null \
  || launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.rakazo.caddy.plist
echo "web:   http://127.0.0.1:5173"
echo "api:   http://127.0.0.1:3100/health"
echo "phone: https://rakazo.czaku.com  (Tailscale on)"
