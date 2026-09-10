#!/usr/bin/env bash
# Rune: ui-commit-guard — PreToolUse Bash hook.
# Refuses 'git commit' when the staged diff contains UI files but no screenshot
# has been captured in PROJECT_SCREENSHOT_DIR within the last 30 minutes.
#
# UI patterns: *View.swift, *Screen.kt, *Screen.tsx, *Page.tsx,
#   paths under /screens/, /views/, /pages/, /components/, *.dart widget files.
#
# Override: commit message contains 'runecode: ui-skip-screenshot --reason <text>'.
# Same audit-trail plumbing as forbidden-language / visual-proof.
# Exit 2 = block. Exit 0 = pass.

input=$(cat)

# ── Audit-log writer (same shape as forbidden-language / visual-proof) ──────
_runecode_audit() {
  local hook_name="$1" reason="$2" details="$3"
  local audit_dir="$HOME/.runecode"
  if ! mkdir -p "$audit_dir" 2>/dev/null; then
    echo "  [audit] WARN: could not create $audit_dir — override not recorded" >&2
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  [audit] WARN: python3 not found — override not recorded" >&2
    return 0
  fi
  HOOK_NAME="$hook_name" REASON="$reason" DETAILS="$details"   AUDIT_FILE="$audit_dir/audit.log" TS="$(date -u +%FT%TZ)"     python3 -c "
import json, os, re, sys

SECRET_PATTERNS = [
    (re.compile(r'sk-ant-[A-Za-z0-9_-]{20,}'), '[REDACTED-ANTHROPIC]'),
    (re.compile(r'sk-[A-Za-z0-9_-]{16,}'), '[REDACTED-KEY]'),
    (re.compile(r'(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}'), '[REDACTED-STRIPE]'),
    (re.compile(r'AKIA[0-9A-Z]{16}'), '[REDACTED-AWS]'),
    (re.compile(r'AIza[0-9A-Za-z_-]{35}'), '[REDACTED-GOOGLE]'),
    (re.compile(r'xox[baprs]-[A-Za-z0-9-]{10,}'), '[REDACTED-SLACK]'),
    (re.compile(r'ghp_[A-Za-z0-9]{16,}'), '[REDACTED-GH-PAT]'),
    (re.compile(r'gho_[A-Za-z0-9]{16,}'), '[REDACTED-GH-OAUTH]'),
    (re.compile(r'(Bearer\s+)[A-Za-z0-9._/+=-]{8,}', re.IGNORECASE), r'\1[REDACTED]'),
    (re.compile(r'(api[_-]?key|password|token|secret)([\s:=]+)[A-Za-z0-9._/+-]{6,}', re.IGNORECASE), r'\1\2[REDACTED]'),
]
CTRL_BYTES = re.compile(
    '['
    '\x00-\x08'
    '\x0b-\x1f'
    '\x7f'
    '\u0080-\u009f'
    '\u200b-\u200f'
    '\u2028-\u202e'
    '\u2066-\u2069'
    '\ufeff'
    ']'
)

def sanitize(s, max_len):
    if not isinstance(s, str):
        s = str(s or '')
    for pat, repl in SECRET_PATTERNS:
        s = pat.sub(repl, s)
    s = CTRL_BYTES.sub('?', s)
    return s[:max_len]

record = {
    'ts': os.environ['TS'],
    'hook': os.environ['HOOK_NAME'],
    'cwd': os.getcwd(),
    'reason': sanitize(os.environ.get('REASON', ''), 200),
    'engine': os.environ.get('RUNECODE_ENGINE', ''),
    'details': sanitize(os.environ.get('DETAILS', ''), 500),
}
try:
    fd = os.open(
        os.environ['AUDIT_FILE'],
        os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW,
        0o600,
    )
except OSError as e:
    sys.stderr.write('  [audit] WARN: could not open audit.log (' + e.__class__.__name__ + ') — override not recorded' + chr(10))
    sys.exit(0)
try:
    os.write(fd, (json.dumps(record) + chr(10)).encode('utf-8'))
finally:
    os.close(fd)
"
}

_runecode_override_notify() {
  local hook_name="$1" reason="$2"
  local msg="runecode override: ${hook_name} bypassed — ${reason}"
  # Always surface on stderr — visible in transcripts/CI even with no GUI/audio.
  echo "  [override] LOUD: ${msg}" >&2
  # GUI/audio side is opt-out (and skipped when there's no controlling TTY env).
  if [[ "${RUNECODE_NO_NOTIFY:-0}" == "1" ]]; then return 0; fi
  _rc_detach() {
    # Run "$@" fully detached: new session if setsid exists, else subshell;
    # all stdio to /dev/null; disown so the parent never waits on it.
    if command -v setsid >/dev/null 2>&1; then
      setsid "$@" </dev/null >/dev/null 2>&1 &
    else
      ( "$@" </dev/null >/dev/null 2>&1 & ) >/dev/null 2>&1
    fi
    disown 2>/dev/null || true
  }
  if [[ "$(uname 2>/dev/null)" == "Darwin" ]]; then
    [[ -f /System/Library/Sounds/Glass.aiff ]] && command -v afplay >/dev/null 2>&1 && \
      _rc_detach afplay /System/Library/Sounds/Glass.aiff
    command -v say >/dev/null 2>&1 && _rc_detach say "runecode override fired for ${hook_name}"
    command -v terminal-notifier >/dev/null 2>&1 && \
      _rc_detach terminal-notifier -title "runecode override" -message "${msg}"
  else
    command -v notify-send >/dev/null 2>&1 && _rc_detach notify-send "runecode override" "${msg}"
    printf '\007' >&2 2>/dev/null || true
  fi
  return 0
}

_runecode_reason_ok() {
  local reason="$1"
  REASON="$reason" python3 -c "
import os, re, sys
raw = os.environ.get('REASON', '') or ''
low = raw.strip().lower()

# Banned filler / placeholder tokens — words that carry no auditable justification.
BANNED = {
    'test', 'tests', 'testing', 'tested', 'wip', 'tmp', 'temp', 'na',
    'none', 'skip', 'skipped', 'override', 'overridden', 'bypass', 'bypassed',
    'allow', 'allowed', 'fixme', 'todo', 'foo', 'bar', 'baz', 'qux', 'asdf',
    'stuff', 'thing', 'things', 'whatever', 'xxx', 'placeholder', 'dummy',
    'reason', 'because', 'just', 'ok', 'okay', 'yes', 'no', 'done', 'good',
}
# Stopwords — meaningful glue but not 'effort' on their own.
STOP = {
    'the', 'a', 'an', 'and', 'or', 'but', 'to', 'of', 'in', 'on', 'at', 'for',
    'with', 'is', 'it', 'this', 'that', 'i', 'we', 'have', 'has', 'was', 'are',
    'be', 'as', 'by', 'so', 'my', 'our', 'its', 'do', 'did',
}

# Outright rejects of the whole string.
if low in ('', '(no reason given)', 'n/a', '.', '...'):
    sys.exit(1)

# Tokenize on non-alphanumeric boundaries; keep alnum tokens of length >= 2
# (a lone letter/digit isn't a meaningful word). '#123' -> '123' counts as a
# token so an issue/PR reference still contributes.
tokens = [t for t in re.findall(r'[a-z0-9]+', low) if len(t) >= 2]
if not tokens:
    sys.exit(1)

# (1) Reject when EVERY token is filler/stopword — e.g. 'test test test test'
#     or 'wip wip wip' are all-banned and carry no justification, even though
#     they clear a raw char count. A reason must contain real signal.
if all((t in BANNED or t in STOP) for t in tokens):
    sys.exit(1)

# (2) Require at least 3 DISTINCT meaningful tokens (not in BANNED/STOP). A char
#     count alone (the old gate) let 'test test test test' through (16 alnum
#     chars); distinctness + meaning is what makes a reason auditable.
meaningful = {t for t in tokens if t not in BANNED and t not in STOP}
if len(meaningful) < 3:
    sys.exit(1)

sys.exit(0)
" 2>/dev/null
}

# ── Tool detection ──────────────────────────────────────────────────────────
tool=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)
[[ "$tool" != "Bash" ]] && exit 0

command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
[[ -z "$command" ]] && exit 0

# Match 'git commit' anywhere in the command (handles wrappers like
# 'env A=B git commit ...', 'cd dir && git commit ...', 'bash -lc "git commit ..."').
# Exclude things like 'git commit-tree' by requiring word-boundary after 'commit'.
if ! echo "$command" | grep -qE '(^|[[:space:]]|;|&|\|)git[[:space:]]+commit($|[[:space:]])'; then
  exit 0
fi

# Inside a git repo?
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Staged files
staged=$(git diff --cached --name-only 2>/dev/null)
[[ -z "$staged" ]] && exit 0

# UI patterns:
#   *View.swift, *Screen.kt, *Screen.tsx, *Page.tsx
#   paths under /screens/, /views/, /pages/, /components/
#   *.dart widget files
ui_pattern='.*View\.swift$|.*Screen\.kt$|.*Screen\.tsx$|.*Page\.tsx$|(^|/)(screens|views|pages|components)/|.*\.dart$'

ui_files=$(echo "$staged" | grep -E "$ui_pattern" || true)
[[ -z "$ui_files" ]] && exit 0

# Override: scoped to the commit MESSAGE only (not anywhere in the bash
# command). Otherwise `echo "runecode: ui-skip-screenshot"; git commit -m
# "feat"` would bypass the guard. Extract -m/--message/-F/--file payloads
# via shlex and apply the override regex to that text only.
commit_message=$(python3 -c "
import sys, shlex
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd)
except Exception:
    sys.exit(0)
parts = []
i = 0
while i < len(tokens):
    t = tokens[i]
    if t in ('-m', '--message'):
        if i + 1 < len(tokens): parts.append(tokens[i + 1]); i += 2; continue
    if t.startswith('--message='):
        parts.append(t[len('--message='):]); i += 1; continue
    if t.startswith('-m') and len(t) > 2 and t[2] != '-':
        parts.append(t[2:]); i += 1; continue
    if t in ('-F', '--file'):
        if i + 1 < len(tokens):
            try:
                with open(tokens[i + 1], encoding='utf-8', errors='replace') as f:
                    parts.append(f.read())
            except Exception:
                pass
            i += 2; continue
    if t.startswith('--file='):
        try:
            with open(t[len('--file='):], encoding='utf-8', errors='replace') as f:
                parts.append(f.read())
        except Exception:
            pass
        i += 1; continue
    i += 1
print('\n'.join(parts))
" <<< "$command" 2>/dev/null)

if echo "$commit_message" | grep -qE 'runecode:[[:space:]]*ui-skip-screenshot\b'; then
  reason=$(echo "$commit_message" | sed -nE 's/.*runecode:[[:space:]]*ui-skip-screenshot[[:space:]]+--reason[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  # Reject trivial reasons — an override must carry a real, auditable justification.
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  ui-commit-guard: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "    Example:      runecode: ui-skip-screenshot --reason 'pure copy tweak in footer, no visual layout change'" >&2
    echo "" >&2
    exit 2
  fi
  files_summary=$(echo "$ui_files" | head -5 | tr '\n' ',' | head -c 300)
  _runecode_audit 'ui-commit-guard' "$reason" "ui_files=$files_summary"
  _runecode_override_notify 'ui-commit-guard' "$reason"
  exit 0
fi

# Resolve screenshot dir
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
shots_dir="${PROJECT_SCREENSHOT_DIR:-$HOME/Desktop/screenshots/$project}"

# Find newest mtime among staged UI files (working-tree state). A screenshot
# older than this can't possibly prove the current change — it predates the
# edit. Block unless newest_shot_mtime >= newest_ui_mtime.
newest_ui_mtime=0
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  if (( m > newest_ui_mtime )); then newest_ui_mtime=$m; fi
done <<< "$ui_files"

newest_shot_mtime=0
fresh_path=""
if [[ -d "$shots_dir" ]]; then
  while IFS= read -r s; do
    [[ -z "$s" || ! -f "$s" ]] && continue
    m=$(stat -f %m "$s" 2>/dev/null || stat -c %Y "$s" 2>/dev/null || echo 0)
    if (( m > newest_shot_mtime )); then newest_shot_mtime=$m; fresh_path="$s"; fi
  done < <(find "$shots_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) 2>/dev/null)
fi

if (( newest_shot_mtime > 0 && newest_shot_mtime >= newest_ui_mtime )); then
  exit 0
fi

echo "" >&2
echo "  ui-commit-guard: BLOCKED — no screenshot newer than the staged UI changes." >&2
echo "    Staged UI files:" >&2
echo "$ui_files" | head -10 | sed 's/^/      - /' >&2
if (( newest_shot_mtime == 0 )); then
  echo "    Screenshot dir:  $shots_dir (no screenshots found)" >&2
else
  ui_when=$(date -r "$newest_ui_mtime" 2>/dev/null || echo "$newest_ui_mtime")
  shot_when=$(date -r "$newest_shot_mtime" 2>/dev/null || echo "$newest_shot_mtime")
  echo "    Screenshot dir:  $shots_dir" >&2
  echo "    Newest staged UI mtime: $ui_when" >&2
  echo "    Newest screenshot mtime: $shot_when (older than the change — re-capture)" >&2
fi
echo "    Fix:             capture a screenshot of the UI change AFTER editing, before committing." >&2
echo "    Override:        include 'runecode: ui-skip-screenshot --reason <text>' in the commit MESSAGE (not just the bash command)." >&2
echo "" >&2
exit 2
