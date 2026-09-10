#!/usr/bin/env bash
# Rune: warn when a Write produces a suspiciously small source file.
# Catches sub-agent stub output (e.g. a 3000-line file replaced with 15 lines).
# PostToolUse — informational only (exit 0), never blocks.

input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

[[ -z "$file" ]] && exit 0

# Only check source files likely to be substantial
echo "$file" | grep -qE '\.(ts|tsx|js|jsx|swift|kt|py|go|rs|java|cs)$' || exit 0

# Count non-empty lines in the written file
[[ -f "$file" ]] || exit 0
line_count=$(grep -c '\S' "$file" 2>/dev/null || true); line_count=${line_count:-0}

# If a source file has fewer than 15 non-blank lines, it may be a stub
if [[ "$line_count" -lt 15 ]]; then
  echo "" >&2
  echo "  sub-agent-guard: $file has only $line_count non-empty lines." >&2
  echo "  If a sub-agent wrote this, verify it is not a stub before continuing." >&2
  echo "  Check: git diff HEAD -- \"$file\" to see what was replaced." >&2
  echo "" >&2
fi

exit 0
