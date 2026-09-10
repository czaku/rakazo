#!/usr/bin/env bash
# Rune: host-check — SessionStart hook.
# Reads setup.intendedHost from the canonical runecode.yaml (or keel/project.json)
# and warns if the current machine ('uname -n') does not match.
# Advisory only (exit 0) — never blocks.

# Resolve project root via git (handles worktrees and submodules where .git is a file)
project_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$project_root" ]] && exit 0

intended=""
# Canonical source: runecode.yaml → setup.intendedHost. 'intendedHost' is a unique
# key in the schema, so a line-scoped grep is a safe YAML-lite read for an
# advisory hook (no YAML parser available in a POSIX shell).
yaml="$project_root/runecode.yaml"
if [[ -f "$yaml" ]]; then
  intended=$(grep -E '^[[:space:]]*intendedHost:[[:space:]]*' "$yaml" 2>/dev/null | head -1 \
    | sed -E 's/^[[:space:]]*intendedHost:[[:space:]]*//; s/[[:space:]]*(#.*)?$//; s/^["'"'"']//; s/["'"'"']$//')
fi
# Fallback: keel/project.json (JSON, keel-owned specialist file).
if [[ -z "$intended" && -f "$project_root/keel/project.json" ]]; then
  intended=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('intendedHost', d.get('intended_host', '')))
except Exception:
    print('')
" "$project_root/keel/project.json" 2>/dev/null)
fi

[[ -z "$intended" ]] && exit 0

current=$(uname -n 2>/dev/null)
[[ -z "$current" ]] && exit 0

# Allow 'either' or 'any' as wildcard
[[ "$intended" == "either" || "$intended" == "any" ]] && exit 0

# Match host (allow short name vs fqdn — current may be 'mac.local', intended 'mac')
short_current="${current%%.*}"
short_intended="${intended%%.*}"
if [[ "$short_current" == "$short_intended" ]]; then
  exit 0
fi

echo "" >&2
echo "  host-check: this project declares intended_host '$intended' but you are on '$current'." >&2
echo "  If this is intentional (cross-machine work), continue. Otherwise SSH to '$intended'." >&2
echo "" >&2

exit 0
