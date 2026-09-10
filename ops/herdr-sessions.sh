#!/bin/zsh
# One-shot login step (T-RKZ-013). The herdr servers themselves are owned by the KeepAlive launch
# agents com.rakazo.herdr-agents and com.rakazo.herdr-agents-kc — this script never starts a server:
# a server started as a child of this job is killed by launchd when the script exits (measured
# 2026-09-10 21:29:57 after the reboot test). It waits for both sessions, ensures the rakazo-lanes
# workspace exists, and logs a Keychain probe (login agents run in the Aqua session: KC=0).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
LOG="$HOME/dev/rakazo-setup/.logs/herdr-sessions.log"
mkdir -p "${LOG:h}"
ts() { date '+%Y-%m-%dT%H:%M:%S'; }
for s in agents agents-kc; do
  up=0
  for i in {1..60}; do herdr --session "$s" pane list >/dev/null 2>&1 && { up=1; break; }; sleep 1; done
  if [ "$up" = 1 ]; then
    echo "$(ts) $s up" >> "$LOG"
    if ! herdr --session "$s" workspace list 2>/dev/null | grep -q '"label":"rakazo-lanes"'; then
      herdr --session "$s" workspace create --label rakazo-lanes >> "$LOG" 2>&1 && echo "$(ts) $s workspace rakazo-lanes created" >> "$LOG"
    fi
  else
    echo "$(ts) $s NOT up after 60s — check launchctl print gui/$(id -u)/com.rakazo.herdr-$s" >> "$LOG"
  fi
done
KC=$(security find-generic-password -s 'Claude Code-credentials' -w >/dev/null 2>&1; echo $?)
echo "$(ts) keychain KC=$KC session=$(launchctl managername)" >> "$LOG"
