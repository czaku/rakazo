#!/usr/bin/env bash
# Rune: ts-safety-guard — PostToolUse Write/Edit hook.
# Catches TypeScript safety bypasses added during a session:
#   - @ts-ignore / @ts-nocheck / @ts-expect-error
#   - as any
# Informational only (exit 0) — warns but does not block.

input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

[[ -z "$file" ]] && exit 0
echo "$file" | grep -qE '.(ts|tsx)$' || exit 0
echo "$file" | grep -qE '(.test.|.spec.|__tests__/)' && exit 0
[[ -f "$file" ]] || exit 0

ISSUES=()

# @ts-ignore / @ts-nocheck / @ts-expect-error
ts_suppress=$(grep -cE '@ts-(ignore|nocheck|expect-error)' "$file" 2>/dev/null || true); ts_suppress=${ts_suppress:-0}
if [[ "$ts_suppress" -gt 0 ]]; then
  ISSUES+=("$ts_suppress @ts-ignore/@ts-nocheck suppression(s) — fix the type error instead")
fi

# as any (in assignments, casts, params — not in generics like Array<any>)
as_any=$(grep -cE '\bas any\b' "$file" 2>/dev/null || true); as_any=${as_any:-0}
if [[ "$as_any" -gt 0 ]]; then
  ISSUES+=("$as_any 'as any' cast(s) — use a proper type or unknown + guard instead")
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo "" >&2
  echo "  ts-safety-guard: $file has TypeScript safety issues:" >&2
  for issue in "${ISSUES[@]}"; do
    echo "    ✗ $issue" >&2
  done
  echo "  These patterns defeat TypeScript's guarantees — fix the types." >&2
  echo "" >&2
fi

exit 0
