#!/usr/bin/env bash
# Rune: codex-destructive-guard — PreToolUse Bash hook.
# When the active engine is codex-* (per RUNECODE_ENGINE env var or HEAD commit
# trailer 'Engine: codex-*'), refuses these git commands:
#   git reset --hard, git push --force, git push -f, git checkout --,
#   git rebase -i, git filter-branch
#
# Source incident: Apr 14-15 2026 lost 517 commits via Codex reset --hard.
# Override: 'runecode: allow-destructive --reason <text>' in the command.
# Exit 2 = block. Exit 0 = pass.

input=$(cat)
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
[[ -z "$command" ]] && exit 0

# Audit-log writer (same shape as forbidden-language).
_runecode_audit() {
  # Append a JSONL audit record. Hardening:
  #   - O_NOFOLLOW + O_CREAT mode 0600: a malicious symlink at audit.log can't
  #     redirect writes, and the file is user-only readable.
  #   - Secrets redaction: strip sk-..., ghp_..., Bearer tokens, common API-key
  #     env-var-style assignments BEFORE writing (defence in depth — the user
  #     might have put them in the override input).
  #   - Control-character strip: zap C0/C1 bytes (incl. ESC) from reason and
  #     details so a hostile input can't seed terminal-injection payloads that
  #     fire when 'runecode overrides' prints the record. JSON.parse restores
  #     raw bytes on read, so we sanitize at write time too.
  #   - Fail loud (not silent): if python3 is missing or the open fails, emit
  #     a stderr line so the agent + 'is audited' claim aren't quietly broken.
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
# Strip C0 + DEL + C1 (U+0080-U+009F) + BiDi controls + zero-width chars.
# C1 includes U+009B which acts like ESC[ on UTF-8 terminals; BiDi overrides
# are the Trojan Source class (CVE-2021-42574); zero-width chars splice
# invisible content. JSON.parse on read restores raw bytes, so we sanitize
# at write time AND at display time (defence in depth).
CTRL_BYTES = re.compile(
    '['
    '\x00-\x08'        # C0 minus tab/LF/CR
    '\x0b-\x1f'        # rest of C0
    '\x7f'              # DEL
    '\u0080-\u009f'    # C1 controls
    '\u200b-\u200f'    # zero-width + LRM/RLM
    '\u2028-\u202e'    # line/paragraph separators + BiDi overrides
    '\u2066-\u2069'    # BiDi isolates
    '\ufeff'            # BOM
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

# Override
if echo "$command" | grep -qE 'runecode:[[:space:]]*allow-destructive\b'; then
  # Capture --reason <text> up to 200 chars. '.' in sed does not match newlines,
  # so the capture stops naturally at line end (issue refs like #123 are kept).
  reason=$(echo "$command" | sed -nE 's/.*runecode:[[:space:]]*allow-destructive[[:space:]]+--reason[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  # P1#4: reason-gate this destructive-op override too — 'allow-destructive
  # --reason test' must be rejected, same bar as every other override.
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  codex-destructive-guard: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "    Example:      runecode: allow-destructive --reason recover from bad merge, see incident #412" >&2
    echo "" >&2
    exit 2
  fi
  _runecode_audit 'codex-destructive-guard' "$reason" "$command"
  _runecode_override_notify 'codex-destructive-guard' "$reason"
  exit 0
fi

# Detect engine — RUNECODE_ENGINE wins, falls back to last commit trailer
engine="${RUNECODE_ENGINE:-}"
if [[ -z "$engine" ]]; then
  engine=$(git log -1 --format='%B' 2>/dev/null | grep -iE '^Engine:[[:space:]]*codex-|^Engine:[[:space:]]*claude-' | head -1 | sed -E 's/Engine:[[:space:]]*//I' | tr -d '[:space:]')
fi

# Only block codex-* engines
case "$engine" in
  codex-*) ;;
  *) exit 0 ;;
esac

# Match destructive patterns
matched=""
if echo "$command" | grep -qE 'git reset --hard\b'; then
  matched="git reset --hard"
elif echo "$command" | grep -qE 'git push --force\b|git push -f\b'; then
  matched="git push --force"
elif echo "$command" | grep -qE 'git checkout --[[:space:]]'; then
  matched="git checkout -- (discards working-tree changes)"
elif echo "$command" | grep -qE 'git rebase -i\b'; then
  matched="git rebase -i"
elif echo "$command" | grep -qE 'git filter-branch\b'; then
  matched="git filter-branch"
fi

[[ -z "$matched" ]] && exit 0

echo "" >&2
echo "  codex-destructive-guard: BLOCKED — engine '$engine' is forbidden from running '$matched'." >&2
echo "" >&2
echo "    Reason:    Apr 15 2026 lost 517 commits to Codex reset --hard." >&2
echo "    Safer:     git revert (reversible) or git reset --soft (commit-preserving)." >&2
echo "    Override:  include 'runecode: allow-destructive --reason <text>' in the command." >&2
echo "" >&2
exit 2
