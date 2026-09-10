#!/usr/bin/env bash
# Rune: no-stubs — PostToolUse Write hook.
# Catches the exact patterns that killed myproject-legacy:
#   - return null; // Placeholder  (5 payment screens shipped as null renders)
#   - Math.random() in production UI  (live nutrition/pulse data was random numbers)
#   - console.log in production source  (110+ left in production native code)
#   - throw new Error("not implemented")  (stub implementations)
#   - TODO: implement / PLACEHOLDER_IMPL
# Informational only (exit 0) — warns but does not block.

input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

[[ -z "$file" ]] && exit 0

# Source files only, not tests, not hooks, not markdown
echo "$file" | grep -qE '[.](ts|tsx|swift|kt|py|js|jsx|go|rs)$' || exit 0
echo "$file" | grep -qE '([.](test|spec)[.]|hooks/|__tests__/)' && exit 0
[[ -f "$file" ]] || exit 0

ISSUES=()

# Stub / not-implemented patterns
if grep -qE 'throw new Error[(]["'"'"'](not implemented|TODO|Not implemented)["'"'"'][)]|// TODO: implement([^[:alnum:]_]|$)|PLACEHOLDER_IMPL|NotImplementedError[(][)]|raise NotImplementedError|pass  # TODO([^[:alnum:]_]|$)' "$file" 2>/dev/null; then
  line=$(grep -nE 'throw new Error[(]["'"'"'](not implemented|TODO)["'"'"'][)]|// TODO: implement([^[:alnum:]_]|$)|PLACEHOLDER_IMPL|NotImplementedError[(][)]|raise NotImplementedError|pass  # TODO([^[:alnum:]_]|$)' "$file" | head -2)
  ISSUES+=("stub implementation found:$line")
fi

# return null placeholder (navigable screen that renders nothing)
if grep -qE 'return null.*[Pp]laceholder|return null.*TODO|return null.*not implemented' "$file" 2>/dev/null; then
  line=$(grep -nE 'return null.*[Pp]laceholder|return null.*TODO' "$file" | head -2)
  ISSUES+=("null placeholder render — screen renders nothing:$line")
fi

# Math.random() in production code (real data replaced with random numbers)
if echo "$file" | grep -qE '[.](ts|tsx|js|jsx|swift|kt)$'; then
  if grep -qE 'Math[.]random[(][)]' "$file" 2>/dev/null; then
    line=$(grep -nE 'Math[.]random[(][)]' "$file" | head -2)
    ISSUES+=("Math.random() in production code — real data source needed:$line")
  fi
fi

# console.log in production source (not tests, not scripts)
if echo "$file" | grep -qE '[.](ts|tsx|js|jsx)$'; then
  if ! echo "$file" | grep -qE '(script|config|hook|util|helper)'; then
    if grep -qE 'console[.](log|warn|error|debug)[(]' "$file" 2>/dev/null; then
      count=$(grep -cE 'console[.](log|warn|error|debug)[(]' "$file" 2>/dev/null || true); count=${count:-0}
      if [[ "$count" -gt 2 ]]; then
        ISSUES+=("$count console.log/warn/error calls in production source — remove before shipping")
      fi
    fi
  fi
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo "" >&2
  echo "  no-stubs: $file has implementation issues:" >&2
  for issue in "${ISSUES[@]}"; do
    label=$(echo "$issue" | cut -d: -f1)
    detail=$(echo "$issue" | cut -d: -f2-)
    echo "    ✗ $label" >&2
    [[ -n "$detail" ]] && echo "      $detail" >&2
  done
  echo "" >&2
  echo "  Complete or remove placeholder code before continuing." >&2
fi

exit 0
