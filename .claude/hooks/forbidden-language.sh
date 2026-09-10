#!/usr/bin/env bash
# Rune: forbidden-language — single hook covering FORBIDDEN_LANGUAGE_PATTERNS.
#
# Branches on tool:
#   - PreToolUse Bash:
#       * banned destructive commands (BLOCK)
#       * git commit messages containing forbidden phrases (BLOCK)
#       * keel task update --status done with no recent screenshot (WARN, exit 0)
#   - PostToolUse Write|Edit:
#       * proof artifacts using "looks correct" / "should work" / etc.
#         WITHOUT a screenshot path (BLOCK)
#
# Override (always allowed): input contains 'runecode: allow' (any reason).
# Whitelist: test files (paths matching test/spec/__tests__) are skipped.
#
# Exit 2 = block. Exit 0 = pass (with optional advisory).
#
# Source incidents (Apr 14-28 2026): local automation failure review
# T1 (visual-proof drift), T3 (linguistic excuses), T4 (destructive Codex ops).

input=$(cat)

# ── Audit-log writer ─────────────────────────────────────────────────────────
# Append a JSONL audit record to ~/.runecode/audit.log when an override fires.
# O_APPEND (bash >>) is atomic for writes < PIPE_BUF (~4KB on POSIX); each
# record is well under that, so concurrent hook invocations don't corrupt the
# log even without explicit locking.
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

# ── Override ────────────────────────────────────────────────────────────────
# Match 'runecode: allow' as a whole token — NOT 'allow-destructive' or any
# 'allow-*' / 'allow_*' variant (those belong to other hooks and would cause
# this hook to spuriously audit under the wrong name). The follow-char must be
# end-of-line OR any character that can't be part of a word/hyphen extension.
if echo "$input" | grep -qE 'runecode:[[:space:]]*allow($|[^a-zA-Z0-9_-])'; then
  # Capture up to 200 chars of reason. Sed's '.' does not match newlines, so
  # the regex stops naturally at end-of-line — important so issue references
  # like '#123' aren't truncated out of the reason text.
  reason=$(echo "$input" | sed -nE 's/.*runecode:[[:space:]]*allow[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  # P1#4: reason-gate this override too — a bypass must carry a substantive,
  # auditable justification (>= 15 meaningful chars; not 'test'/empty).
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  forbidden-language: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "    Example:      runecode: allow recovering accidental commit from autosave, see incident #412" >&2
    echo "" >&2
    exit 2
  fi
  _runecode_audit 'forbidden-language' "$reason" "$(echo "$input" | head -c 500)"
  _runecode_override_notify 'forbidden-language' "$reason"
  exit 0
fi

# ── Tool detection ───────────────────────────────────────────────────────────
tool=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)

# ── PostToolUse Write|Edit: proof-artifact phrases without screenshot path ──
if [[ "$tool" == "Write" || "$tool" == "Edit" ]]; then
  # kimi-code Write/Edit payloads carry 'path' (Claude uses 'file_path') — take either.
  file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

  # Whitelist: test files
  if echo "$file" | grep -qE '(\.test\.|\.spec\.|/__tests__/|/test/|/tests/)'; then
    exit 0
  fi

  # Only check text-ish artifacts where proof claims live (md, txt, keel notes)
  if ! echo "$file" | grep -qE '\.(md|txt|json|yml|yaml)$'; then
    exit 0
  fi

  # Extract written content (Write: 'content', Edit: 'new_string')
  content=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', d.get('input', {}))
    print(ti.get('content', ti.get('new_string', '')))
except Exception:
    print('')
" 2>/dev/null)
  [[ -z "$content" ]] && exit 0

  # Detect proof phrases
  proof_match=$(echo "$content" | grep -niE 'looks correct|should work|rendered successfully|visually verified' | head -1)
  if [[ -n "$proof_match" ]]; then
    # Allow if a screenshot path is present nearby (.png, .jpg, screenshots/)
    if echo "$content" | grep -qiE '\.(png|jpg|jpeg|webp)\b|/screenshots?/|PROJECT_SCREENSHOT_DIR'; then
      exit 0
    fi
    line_num=$(echo "$proof_match" | cut -d: -f1)
    pattern=$(echo "$proof_match" | cut -d: -f2- | sed 's/^[[:space:]]*//' | head -c 120)
    echo "" >&2
    echo "  forbidden-language: BLOCKED — proof phrase used without screenshot path." >&2
    echo "    File:    $file:$line_num" >&2
    echo "    Match:   $pattern" >&2
    echo "    Reason:  'looks correct' / 'should work' is not proof. A screenshot IS." >&2
    echo "    Fix:     attach a screenshot path (e.g. ~/Desktop/screenshots/...) or rephrase." >&2
    echo "    Override: include 'runecode: allow <reason>' to bypass." >&2
    echo "" >&2
    exit 2
  fi
  exit 0
fi

# ── PreToolUse Bash ─────────────────────────────────────────────────────────
if [[ "$tool" == "Bash" ]]; then
  command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
  [[ -z "$command" ]] && exit 0

  # Banned destructive commands
  banned_match=""
  if echo "$command" | grep -qE 'git reset --hard\b'; then
    banned_match="git reset --hard"
  elif echo "$command" | grep -qE 'git push --force\b|git push -f\b|git push [^|]*--force-with-lease\b'; then
    banned_match="git push --force"
  elif echo "$command" | grep -qE 'rm -rf[[:space:]]+\.git\b'; then
    banned_match="rm -rf .git"
  elif echo "$command" | grep -qE 'rm -rf[[:space:]]+([./]+)?node_modules\b' && ! echo "$command" | grep -qE -- '--force[-_]?confirm\b'; then
    banned_match="rm -rf node_modules (without --force-confirm)"
  fi

  if [[ -n "$banned_match" ]]; then
    echo "" >&2
    echo "  forbidden-language: BLOCKED — banned destructive command." >&2
    echo "    Command:  $command" >&2
    echo "    Pattern:  $banned_match" >&2
    echo "    Reason:   destructive ops in this list cost real work in past incidents." >&2
    echo "    Fix:      use git revert / git reset --soft / explicit confirmation." >&2
    echo "    Override: include 'runecode: allow <reason>' to bypass." >&2
    echo "" >&2
    exit 2
  fi

  # Forbidden phrases in git commit messages.
  # Approach: detect 'git commit' anywhere in the command (handles wrappers like
  # 'env A=B git commit ...', 'bash -lc "git commit ..."', or 'cd dir && git commit ...').
  # Then grep the whole command body (which includes -m "..." inline OR a heredoc body)
  # for forbidden phrases. False positives are acceptable — the override comment is the escape hatch.
  if echo "$command" | grep -qE '(^|[[:space:]]|;|&|\|)git[[:space:]]+commit\b'; then
    forbidden=$(echo "$command" | grep -niE 'pre-existing|out of scope|for now\b|will fix later|table this|TODO:[[:space:]]*fix|skipping for now' | head -1)
    if [[ -n "$forbidden" ]]; then
      line_num=$(echo "$forbidden" | cut -d: -f1)
      pattern=$(echo "$forbidden" | cut -d: -f2- | sed 's/^[[:space:]]*//' | head -c 120)
      echo "" >&2
      echo "  forbidden-language: BLOCKED — commit message uses excuse phrasing." >&2
      echo "    Line:    commit-msg:$line_num" >&2
      echo "    Match:   $pattern" >&2
      echo "    Reason:  these phrases are how regressions sneak through. Fix or scope it." >&2
      echo "    Override: include 'runecode: allow <reason>' to bypass." >&2
      echo "" >&2
      exit 2
    fi
  fi

  # PreToolUse on keel task update *--status done — advisory (no block).
  # Equals-form tolerance (P1-A): match '--status done' AND '--status=done' (and
  # '--run-status'/'-s'), so the advisory fires on the same forms the hard gate does.
  if echo "$command" | grep -qE 'keel[[:space:]]+task[[:space:]]+update.*(--status|--run-status|-s)[[:space:]=]+done'; then
    project=$(basename "$PWD" 2>/dev/null)
    # Honor PROJECT_SCREENSHOT_DIR — same precedence as visual-proof (consistent UX)
    shots_dir="${PROJECT_SCREENSHOT_DIR:-$HOME/Desktop/screenshots/$project}"
    has_recent_proof=0
    if [[ -d "$shots_dir" ]]; then
      # Any screenshot in the last 30 minutes counts as "proof attached this session"
      if find "$shots_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) -mmin -30 2>/dev/null | head -1 | grep -q .; then
        has_recent_proof=1
      fi
    fi
    if [[ "$has_recent_proof" == "0" ]]; then
      echo "" >&2
      echo "  forbidden-language: keel task update --status done — no recent screenshot proof." >&2
      echo "    Looked in: $shots_dir (within last 30 min)" >&2
      echo "    Suggestion: attach a screenshot before marking done, OR include 'runecode: allow' if N/A." >&2
      echo "" >&2
      # Advisory only — exit 0 (do not block)
    fi
  fi

  exit 0
fi

exit 0
