#!/bin/zsh
# Starts the self-hosted Rakazo production stack on the Mac Studio + Caddy front door.
# Canonical URL: https://rakazo.czaku.com (Caddy launch agent com.rakazo.caddy, LE cert via Cloudflare DNS-01)
# Web is served two ways in production: a static build (`pnpm --filter @rakazo/web build` ->
# apps/web/dist) that Caddy serves directly for everything, PLUS `vite preview` kept running only
# so Caddy can route /novnc/* to it (see ops/Caddyfile.rakazo-block for why — the noVNC proxy logic
# lives only inside Vite's own Node process). This script does not invoke `vite preview` itself —
# com.rakazo.web.plist does, pinned to --host 127.0.0.1 --port 5173 --strictPort (vite.config.ts's
# preview.host default is 0.0.0.0/all-interfaces; the plist's CLI flags override that, loopback
# only, since preview is reached solely via Caddy's local reverse_proxy). api/worker/
# sandbox-supervisor/web all run via their `start`/`preview` scripts (no watch/dev mode) as
# launchd KeepAlive agents (ops/launchd/*.plist) instead of a single nohup'd `pnpm dev`. This
# script rebuilds the web bundle, (re)starts Postgres, and kickstarts the launchd agents.
set -e
PORT=31415  # Caddy TLS port; tailscaled forwards :443 -> 127.0.0.1:31415 (tailscale serve --tcp=443), so URLs carry no port
if lsof -nP -iTCP:$PORT -sTCP:LISTEN | awk 'NR>1 && $1!="caddy"' | grep -q .; then echo "PORT $PORT is held by another process:"; lsof -nP -iTCP:$PORT -sTCP:LISTEN; exit 1; fi
cd "$HOME/dev/rakazo-setup/rakazo"
mkdir -p "$HOME/dev/rakazo-setup/.logs"
docker compose --env-file .env -f infra/compose/docker-compose.yml \
  -f infra/compose/docker-compose.postgres-host.local.yml up postgres -d

pnpm --filter @rakazo/web build

for agent in com.rakazo.api com.rakazo.worker com.rakazo.sandbox-supervisor com.rakazo.web; do
  launchctl kickstart -k "gui/$(id -u)/$agent" 2>/dev/null \
    || launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist"
done

tailscale serve --bg --tcp=443 tcp://127.0.0.1:31415
launchctl kickstart "gui/$(id -u)/com.rakazo.caddy" 2>/dev/null \
  || launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.rakazo.caddy.plist
echo "api:   http://127.0.0.1:3100/health"
echo "web:   http://127.0.0.1:5173  (novnc proxy only; everything else is static apps/web/dist via Caddy)"
echo "phone: https://rakazo.czaku.com  (Tailscale on)"
