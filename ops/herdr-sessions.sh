#!/bin/zsh
# Recreates the herdr worker sessions after login (T-RKZ-013). Idempotent: a session that already
# answers is left alone. Started by the login agent com.rakazo.herdr-sessions in the Aqua session,
# which can read the login Keychain (measured KC=0), so subscription lanes can log in in both sessions.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
LOG="$HOME/dev/rakazo-setup/.logs/herdr-sessions.log"
mkdir -p "${LOG:h}"
ts() { date '+%Y-%m-%dT%H:%M:%S'; }
for s in agents agents-kc; do
  if herdr --session "$s" pane list >/dev/null 2>&1; then
    echo "$(ts) $s already running" >> "$LOG"
  else
    nohup herdr --session "$s" server >> "$LOG" 2>&1 &
    for i in {1..20}; do herdr --session "$s" pane list >/dev/null 2>&1 && break; sleep 1; done
    echo "$(ts) $s started" >> "$LOG"
  fi
  if ! herdr --session "$s" workspace list 2>/dev/null | grep -q '"label":"rakazo-lanes"'; then
    herdr --session "$s" workspace create --label rakazo-lanes >> "$LOG" 2>&1 && echo "$(ts) $s workspace rakazo-lanes created" >> "$LOG"
  fi
done
KC=$(security find-generic-password -s 'Claude Code-credentials' -w >/dev/null 2>&1; echo $?)
echo "$(ts) keychain KC=$KC session=$(launchctl managername)" >> "$LOG"
