#!/usr/bin/env bash
# Rune: mobile-screenshot-reminder — PostToolUse Write/Edit hook.
# After editing a Swift or Kotlin UI file, reminds Claude to screenshot the result.
# Informational only (exit 0).

input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

[[ -z "$file" ]] && exit 0

# Only trigger on Swift/Kotlin/SwiftUI source files that are likely UI
echo "$file" | grep -qE '.(swift|kt|kts)$' || exit 0

# Filter to likely view/screen files
filename=$(basename "$file")
echo "$filename" | grep -qiE '(View|Screen|Component|Widget|Activity|Fragment|Page|Scene).(swift|kt|kts)$' || exit 0

echo "" >&2
echo "  mobile-screenshot-reminder: $filename was edited." >&2
echo "  Screenshot the simulator to verify visual output before continuing:" >&2
echo "    /mobile-run  — screenshot + visual QA" >&2
echo "    /pixel-perfection-audition  — measure rendered visual quality" >&2
echo "" >&2

exit 0
