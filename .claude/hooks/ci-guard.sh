#!/usr/bin/env bash
# Rune: ci-guard — PreToolUse Write/Edit hook.
# Blocks the one pattern that is never legitimate:
#   - continue-on-error: true in CI steps — makes CI appear to run while blocking nothing.
#     This is the silent sabotage: checks look green, nothing actually fails the build.
#
# Does NOT block disabling or deleting workflows — that is a legitimate user choice
# (e.g. stopping email spam from failing CI on an early-stage project).
#
# Exit code 2 = block + message.

input=$(cat)

file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)
[[ -z "$file" ]] && exit 0

# Only care about workflow YAML files
echo "$file" | grep -qE '.github/(workflows|actions)/.+.(yml|yaml)$' || exit 0

# Extract written content
content=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('content', ti.get('new_string', '')))" 2>/dev/null)
[[ -z "$content" ]] && exit 0

# Block continue-on-error: true — makes CI structurally non-blocking
# This is never the right fix. If a step is noisy, disable the whole workflow instead.
if echo "$content" | grep -qE 'continue-on-error:[[:space:]]*true'; then
  echo "ci-guard: blocked — continue-on-error: true makes CI non-blocking." >&2
  echo "This makes checks appear to run while never actually failing the build." >&2
  echo "If you want to silence noisy CI: disable the whole workflow file instead." >&2
  echo "If this is intentional, remove this hook or override manually." >&2
  exit 2
fi

exit 0
