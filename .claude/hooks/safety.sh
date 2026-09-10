#!/usr/bin/env bash
# Rune: block dangerous commands before Claude runs them
# Exit code 2 = block the action and show this message to Claude

DANGEROUS_PATTERNS='rm -rf /|rm -rf ~|DROP TABLE|DELETE FROM .* WHERE 1=1|git push --force origin main|git push -f origin main'

input=$(cat)
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
[[ -z "$command" ]] && exit 0

if echo "$command" | grep -qE "$DANGEROUS_PATTERNS"; then
  echo "Blocked by Rune safety hook: command looks dangerous. Be more specific." >&2
  exit 2
fi

# Block pkill -f — too broad, can kill unrelated terminal windows and processes
# Use: kill $(lsof -ti:<port>)  or  pkill -x <exact-name>  instead
if echo "$command" | grep -qE 'pkill\s+-[a-zA-Z]*f'; then
  echo "Blocked by Rune safety hook: pkill -f is too broad — it matches full command lines" >&2
  echo "and can kill unrelated terminal windows." >&2
  echo "Use instead: kill \$(lsof -ti:<port>)  or  pkill -x <exact-process-name>" >&2
  exit 2
fi
