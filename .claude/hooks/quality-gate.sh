#!/usr/bin/env bash
# Rune: quality gate — Stop hook, runs before Claude declares a session complete.
# Enforces: no stubs in changed files, TypeScript clean, tests not regressed.
# Exit code 2 = block session end and show message to Claude.

# Every git query below is pinned to the PROJECT, never the ambient shell cwd.
# Without this the hook reports on whatever directory the session happened to be
# sitting in — including a lane worktree where a parallel worker is mid-edit —
# and demands that somebody else's half-finished work be committed. In a repo
# that does parallel work in worktrees, uncommitted changes in a lane are the
# NORMAL state, not a fault.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]] || exit 0
git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# A worktree of the project is NOT the project: its checkout is a separate
# working tree with its own in-flight state, and this gate speaks only for the
# main one.
project_toplevel=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
[[ "$project_toplevel" == "$PROJECT_DIR" ]] || exit 0

ISSUES=()

# ── 0. Uncommitted work check ────────────────────────────────────────────────
# Blocks session end if source files have been modified but never committed.
# Agents routinely do a day of work without committing. This catches it.
uncommitted=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null | grep -vE '^[[:space:]]*$')
untracked=$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null | grep -E '[.](ts|tsx|swift|kt|py|js|jsx|go|rs)$')

if [[ -n "$uncommitted" ]] || [[ -n "$untracked" ]]; then
  file_count=$(( $(echo "$uncommitted" | grep -c '.') + $(echo "$untracked" | grep -c '.') ))
  # Only flag if there are source-code changes (not just config/lockfile noise)
  src_changes=$(echo "$uncommitted $untracked" | tr ' ' '
' | grep -cE '[.](ts|tsx|swift|kt|py|js|jsx|go|rs|md)$' || true); src_changes=${src_changes:-0}
  if [[ "$src_changes" -gt 0 ]]; then
    ISSUES+=("$src_changes changed file(s) not committed (source or markdown) — commit before declaring done")
  fi
fi

# ── 1. Stub / placeholder detection ─────────────────────────────────────────
# Skip the hook scripts themselves and generated files
changed=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null | grep -v '^$')
STUB_PATTERNS='throw new Error[(]"not implemented"[)]|throw new Error[(]"TODO"[)]|// TODO: implement([^[:alnum:]_]|$)|PLACEHOLDER_IMPL|NotImplementedError[(][)]|pass  # TODO([^[:alnum:]_]|$)|raise NotImplementedError'

for f in $changed; do
  [[ -f "$f" ]] || continue
  # Only source files, not test files, not the hook itself, not markdown
  echo "$f" | grep -qE '[.](ts|tsx|swift|kt|py|js|jsx|go|rs)$' || continue
  echo "$f" | grep -qE '(test|spec|[.]sh|hooks/)' && continue
  if grep -qE "$STUB_PATTERNS" "$f" 2>/dev/null; then
    ISSUES+=("stub in $f — contains NOT IMPLEMENTED / TODO: implement / placeholder")
  fi
done

# ── 2. TypeScript: must compile clean ───────────────────────────────────────
if echo "$changed" | grep -qE '[.](ts|tsx)$'; then
  if command -v tsc >/dev/null 2>&1 && [[ -f "tsconfig.json" ]]; then
    ts_errors=$(tsc --noEmit 2>&1 | grep -c "error TS" || true); ts_errors=${ts_errors:-0}
    if [[ "$ts_errors" -gt 0 ]]; then
      ISSUES+=("$ts_errors TypeScript error(s) — run: tsc --noEmit")
    fi
  fi
fi

# ── 3. Changed-test reminder ─────────────────────────────────────────────────
# NOT a regression check, and no longer described as one. It previously claimed
# to "check that test count didn't drop vs HEAD" while actually counting CHANGED
# TEST FILES and firing whenever that count was above zero — a comment that lied
# about the code, and an unconditional block on any session that touched a test.
# Running the suite from a Stop hook is not viable (this repo's takes minutes and
# apps/cli needs --no-file-parallelism), so it states the reminder honestly
# instead of pretending to measure something.
if echo "$changed" | grep -qE '[.](test|spec)[.](ts|tsx|js|py|swift|kt)$'; then
  ISSUES+=("test files changed — run the suite and confirm counts before declaring done (this hook does NOT run it)")
fi

# ── Report ───────────────────────────────────────────────────────────────────
if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo "" >&2
  echo "  quality-gate: session blocked — resolve these before declaring done:" >&2
  for issue in "${ISSUES[@]}"; do
    echo "    ✗ $issue" >&2
  done
  echo "" >&2
  echo "  Fix the issues above, then confirm completion." >&2
  exit 2
fi

exit 0
