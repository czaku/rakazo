#!/usr/bin/env bash
# Rune: mcp-close-guard — PreToolUse hook for MCP tool calls.
#
# CLOSES THE STRUCTURAL BYPASS: done-needs-proof matches only Bash, so closing
# a task via the keel MCP tool (mcp__keel__update_task { status: "done" }) or a
# GitHub MCP close tool NEVER tripped the gate. This hook applies the SAME
# human-surface proof check to MCP task-completion, tool-agnostically (works for
# Codex and any client that drives keel/GitHub over MCP rather than the CLI).
#
# Triggers (tool_name + tool_input together):
#   - mcp__*keel* / keel_update_task / *update_task  WITH status == done/closed/complete
#   - mcp__*github*/*git* issue/PR close tools (close_issue, update_issue state=closed,
#     merge_pull_request, update_pull_request state=closed)
#
# Proof channels are identical to done-needs-proof (screenshot / e2e file in diff /
# human-surface commit excerpt / proof artifact / atlas capture) with the same
# UI-surface escalation (UI diff requires a screenshot or atlas capture).
#
# Override: include 'runecode: allow-done --reason <text>' anywhere in tool_input
# (e.g. in the note/comment field). Reason must be substantive (Fix #2).
# Exit 2 = block. Exit 0 = pass.

input=$(cat)

# Whether python3 is available — gates the structured path vs the bash fallback.
have_py=0
command -v python3 >/dev/null 2>&1 && have_py=1

# ── Tool name (P1#3: fail-CLOSED, with a pure-bash fallback) ─────────────────
tool=""
if [[ "$have_py" == "1" ]]; then
  tool=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)
fi
if [[ -z "$tool" ]]; then
  # python3 absent or parse failed — grep the raw JSON for the tool name.
  tool=$(printf '%s' "$input" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
fi
# If we still cannot identify the tool, we cannot know it is a close — but the
# PreToolUse matcher only routes MCP/close-ish tools here, so a missing name
# means an unexpected payload shape. Exit 0 only when the raw input shows no
# close/done intent at all; otherwise fall through and require proof (below).
[[ -z "$tool" ]] && ! echo "$input" | grep -qiE '"([a-z_]*status|[a-z_]*state|new_state|runstatus)"[[:space:]]*:[[:space:]]*"(done|closed|complete|completed|merged)"|close_issue|merge_pull_request|_close' && exit 0

# Only consider MCP tools (or bare keel/gh MCP tool names) — Bash is done-needs-proof's job.
# (When $tool is empty but the raw input shows close intent we still proceed.)
if [[ -n "$tool" ]]; then
  echo "$tool" | grep -qiE '^mcp__|update_task|close_issue|update_issue|update_pull_request|merge_pull_request|^keel_|_close$' || exit 0
fi

# ── Status/close detection + flattened blob ──────────────────────────────────
# P1#3: scan ALL status/state-like fields RECURSIVELY (top-level AND nested).
# If ANY equals a close/done value (done/closed/complete/completed/merged), this
# is a close — so {status:"open", state:"closed"} and {task:{status:"done"}} are
# both caught, and first-field-wins can no longer hide a close behind an "open".
status_close=0
blob=""
if [[ "$have_py" == "1" ]]; then
  read -r -d '' _PYDETECT <<'PY' || true
import sys, json
CLOSE = {'done', 'closed', 'complete', 'completed', 'merged'}
# P2 (status key coverage): match the canonical status/state keys AND any key
# whose NAME ENDS in 'status' or 'state' (task_status, item_state, board_state,
# ...). A composite-keyed close like {task_status:"done"} is now detected.
def is_status_key(k):
    lk = str(k).lower()
    return lk in {'status', 'state', 'new_state', 'run_status', 'runstatus'} or lk.endswith('status') or lk.endswith('state')
try:
    d = json.load(sys.stdin)
except Exception:
    # P2 (parse-fail fail-open seam): python is present but the payload did not
    # parse (e.g. truncated JSON). Signal PARSED=0 so the caller runs the raw-grep
    # bash fallback instead of trusting CLOSE=0 — a malformed close must not pass.
    print("PARSED=0"); print("BLOB="); print("CLOSE=0"); sys.exit(0)
ti = d.get('tool_input', d.get('input', d))
close = 0
def walk(x):
    global close
    if isinstance(x, dict):
        for k, v in x.items():
            if is_status_key(k) and isinstance(v, (str, int)) and str(v).strip().lower() in CLOSE:
                close = 1
            walk(v)
    elif isinstance(x, (list, tuple)):
        for v in x:
            walk(v)
walk(ti)
# Task id being closed (P1#1b) — first id/task_id/issue_number/pr/number field.
task_id = ''
TASK_KEYS = ('id', 'task_id', 'taskid', 'issue_number', 'pull_number', 'pr', 'pr_number', 'number', 'key', 'task')
def find_task(x):
    global task_id
    if task_id:
        return
    if isinstance(x, dict):
        for k, v in x.items():
            if str(k).lower() in TASK_KEYS and isinstance(v, (str, int)) and str(v).strip():
                task_id = str(v).strip(); return
        for v in x.values():
            find_task(v)
    elif isinstance(x, (list, tuple)):
        for v in x:
            find_task(v)
find_task(ti)
def flat(x):
    if isinstance(x, dict):
        return ' '.join(f'{k}={flat(v)}' for k, v in x.items())
    if isinstance(x, (list, tuple)):
        return ' '.join(flat(v) for v in x)
    return str(x)
blob = flat(ti) if isinstance(ti, (dict, list, tuple)) else str(ti)
print('PARSED=1')
print('CLOSE=' + str(close))
print('TASK=' + task_id)
print('BLOB=' + blob.replace(chr(10), ' ')[:2000])
PY
  detect=$(echo "$input" | python3 -c "$_PYDETECT" 2>/dev/null)
  py_parsed=$(printf '%s\n' "$detect" | sed -nE 's/^PARSED=(.*)$/\1/p' | head -1)
  status_close=$(printf '%s\n' "$detect" | sed -nE 's/^CLOSE=(.*)$/\1/p' | head -1)
  close_task_id=$(printf '%s\n' "$detect" | sed -nE 's/^TASK=(.*)$/\1/p' | head -1)
  blob=$(printf '%s\n' "$detect" | sed -nE 's/^BLOB=(.*)$/\1/p' | head -1)
  [[ -z "$status_close" ]] && status_close=0
  # P2 (parse-fail fail-open seam): if python3 was present but did NOT parse the
  # payload (PARSED!=1 — truncated/garbled JSON, or the script itself failed and
  # printed nothing), fall through to the raw-grep fallback below instead of
  # trusting CLOSE=0. Previously this seam only ran when python was absent.
  if [[ "$py_parsed" != "1" ]]; then
    have_py=0
  fi
fi
if [[ "$have_py" == "0" ]]; then
  # Pure-bash fallback (P1#3 + P2 parse-fail): grep the raw JSON for a status/
  # state key set to a done/closed value, anywhere (nesting is irrelevant to a
  # flat regex scan). P2 (status key coverage): match the canonical keys AND any
  # key whose NAME ENDS in 'status'/'state' (e.g. task_status) — '[a-z_]*status'.
  if echo "$input" | grep -qiE '"([a-z_]*status|[a-z_]*state|new_state|runstatus)"[[:space:]]*:[[:space:]]*"(done|closed|complete|completed|merged)"'; then
    status_close=1
  fi
  # Task id (P1#1b) — first id/task_id/issue_number/number field in the raw JSON.
  close_task_id=$(printf '%s' "$input" | sed -nE 's/.*"(id|task_id|taskid|issue_number|pull_number|pr_number|number|key|task)"[[:space:]]*:[[:space:]]*"?([A-Za-z0-9._-]+)"?.*/\2/p' | head -1)
  # Blob = the raw JSON (used only for override + diagnostics).
  blob=$(printf '%s' "$input" | tr '\n' ' ' | head -c 2000)
fi

# Decide whether this MCP call is a "claiming done / closing" action.
is_close=0
trigger_kind=""
if echo "$tool" | grep -qiE 'update_task|^keel_|keel'; then
  [[ "$status_close" == "1" ]] && { is_close=1; trigger_kind="mcp-keel-done"; }
elif echo "$tool" | grep -qiE 'close_issue|merge_pull_request|_close$'; then
  is_close=1; trigger_kind="mcp-gh-close"
elif echo "$tool" | grep -qiE 'update_issue|update_pull_request'; then
  [[ "$status_close" == "1" ]] && { is_close=1; trigger_kind="mcp-gh-close"; }
elif [[ -z "$tool" && "$status_close" == "1" ]]; then
  # Tool name unknown but the payload carries explicit close/done intent — treat
  # as a close and require proof (P1#3: do not silently pass).
  is_close=1; trigger_kind="mcp-unknown-close"
fi

[[ "$is_close" == "0" ]] && exit 0

# Audit-log writer (same shape/hardening as done-needs-proof).
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
  HOOK_NAME="$hook_name" REASON="$reason" DETAILS="$details" \
  AUDIT_FILE="$audit_dir/audit.log" TS="$(date -u +%FT%TZ)" \
    python3 -c "
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
CTRL_BYTES = re.compile('[\x00-\x08\x0b-\x1f\x7f\u0080-\u009f\u200b-\u200f\u2028-\u202e\u2066-\u2069\ufeff]')
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
    fd = os.open(os.environ['AUDIT_FILE'], os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
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

_runecode_validate_artifact() {
  local f="$1"
  # Must exist and be a non-empty regular file.
  [[ -f "$f" ]] || return 1
  [[ -s "$f" ]] || return 1
  local lower
  lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *.zip)
      # Real ZIP: prefer unzip -t; fall back to PK magic bytes (50 4b 03 04 /
      # 50 4b 05 06 empty / 50 4b 07 08 spanned).
      if command -v unzip >/dev/null 2>&1; then
        unzip -t -q "$f" >/dev/null 2>&1 && return 0
        return 1
      fi
      local magic
      magic=$(head -c 4 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
      case "$magic" in
        504b0304|504b0506|504b0708) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *.webm)
      # EBML magic: 1a 45 df a3
      local magic
      magic=$(head -c 4 "$f" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
      [[ "$magic" == "1a45dfa3" ]] && return 0
      return 1
      ;;
    *.mp4)
      # ISO-BMFF: 'ftyp' box type at bytes 4-7.
      local box
      box=$(dd if="$f" bs=1 skip=4 count=4 2>/dev/null)
      [[ "$box" == "ftyp" ]] && return 0
      return 1
      ;;
    *junit*.xml|*report*.xml|*.xml)
      # A real test report names a suite / test count / result.
      grep -qiE '<testsuites?\b|tests="[0-9]+"|<testcase\b|failures="[0-9]+"|skipped="[0-9]+"' "$f" 2>/dev/null && return 0
      return 1
      ;;
    results*.json|*results*.json|*.json)
      # A real results JSON carries a test/pass/total marker.
      grep -qiE '"(numpassedtests|numtotaltests|numfailedtests|passed|failed|total|tests|stats|expected|status)"[[:space:]]*:' "$f" 2>/dev/null && return 0
      # Some runners emit HTTP transcripts as JSON — accept a real 2xx too.
      grep -qiE 'HTTP/[0-9.]+[[:space:]]+2[0-9][0-9]\b|"status"[[:space:]]*:[[:space:]]*2[0-9][0-9]\b' "$f" 2>/dev/null && return 0
      return 1
      ;;
    *curl*|*.http|*status*|*.log|*.txt)
      # HTTP/curl transcript: require a real success status line.
      # Matches: 'HTTP/1.1 200 OK', 'HTTP/2 204', '< HTTP/2 200', 'HTTP/2 200'.
      grep -qiE '(^|[^0-9])HTTP/[0-9](\.[0-9])?[[:space:]]+2[0-9][0-9]\b|<[[:space:]]+HTTP/[0-9](\.[0-9])?[[:space:]]+2[0-9][0-9]\b' "$f" 2>/dev/null && return 0
      return 1
      ;;
    maestro*|*.mp4|*.mov)
      # Media-ish maestro artifact: a non-empty file already passed the -s gate;
      # require it to be larger than a trivial text smear.
      local sz
      sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
      [[ "${sz:-0}" -gt 256 ]] && return 0
      return 1
      ;;
    *)
      # Unrecognised — fail closed.
      return 1
      ;;
  esac
}

_runecode_task_in_path() {
  local p="$1" id="$2"
  [[ -z "$id" ]] && return 0  # no id to bind to → caller treats as unbound
  # Escape regex metacharacters that can appear in an id ('.' is the only one in
  # [A-Za-z0-9._-]); everything else is literal.
  local q
  q=$(printf '%s' "$id" | sed 's/[.]/\\./g')
  printf '%s' "$p" | grep -qE "(^|/)${q}(/|\$|[._-])"
}

# Override path — accept 'runecode: allow-done --reason <text>' anywhere in the
# flattened MCP input (e.g. inside a note/comment field), with reason validation.
if echo "$blob" | grep -qE 'runecode:[[:space:]]*allow-done\b'; then
  reason=$(echo "$blob" | sed -nE 's/.*runecode:[[:space:]]*allow-done[[:space:]]+--reason[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  mcp-close-guard: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "" >&2
    exit 2
  fi
  _runecode_audit 'mcp-close-guard' "$reason" "trigger=$trigger_kind tool=$tool"
  _runecode_override_notify 'mcp-close-guard' "$reason"
  exit 0
fi

# A close was requested. If this is NOT a git repo we cannot read a diff to find
# proof — and P1#3 says a non-git cwd on a close attempt must NOT be a free pass.
# Block and tell the operator to use the audited override.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "" >&2
  echo "  mcp-close-guard: BLOCKED — MCP task-close ($trigger_kind, tool: ${tool:-?}) outside a git repo." >&2
  echo "    Why:      proof is read from the repo's recent diff / proof artifacts; with no repo there is" >&2
  echo "              nothing to verify, so closing here cannot be proven (P1#3: not a free pass)." >&2
  echo "    Fix:      run the close from inside the project's git working tree, OR" >&2
  echo "    Override: put 'runecode: allow-done --reason <text>' in the tool's note/comment field (audited)." >&2
  echo "" >&2
  exit 2
fi

stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

now_epoch=$(date +%s)
recent_cutoff=$((now_epoch - 1800))  # 30 minutes

# ── Evidence channel 1: recent screenshot in PROJECT_SCREENSHOT_DIR ──────────
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
shots_dir="${PROJECT_SCREENSHOT_DIR:-$HOME/Desktop/screenshots/$project}"
has_recent_shot=0
if [[ -d "$shots_dir" ]]; then
  while IFS= read -r shot; do
    [[ -f "$shot" ]] || continue
    m=$(stat_mtime "$shot")
    if [[ "$m" -gt "$recent_cutoff" ]]; then has_recent_shot=1; break; fi
  done < <(find "$shots_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.mp4' -o -name '*.gif' \) 2>/dev/null)
fi

# ── Evidence channel 2: e2e/integration test in THIS change set (Fix #3) ─────
# Same hardening as done-needs-proof: an e2e file path alone is the weakest
# signal, so we only count files in the uncommitted working tree or the single
# most-recent commit — NOT anywhere in the last 10 commits.
e2e_pattern='(e2e|E2E|integration|Integration|journey|Journey|flow|Flow|acceptance|Acceptance|ui-test|UITest|xcuitest|XCUITest|espresso|Espresso|detox|Detox|playwright|Playwright|cypress|Cypress|webdriver|WebDriver)'
has_e2e=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if echo "$f" | grep -qE "$e2e_pattern"; then has_e2e=1; break; fi
done < <( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; git show --name-only --format='' HEAD 2>/dev/null; } | sort -u )

# ── Evidence channel 3: REMOVED (P1#5) ──────────────────────────────────────
# A commit-body text claim is NOT proof — the same removal as done-needs-proof.
# Prose like "journey passed" can no longer close an MCP task by itself.

# ── Evidence channel 4: explicit proof artifact, recent + task-bound ─────────
# Markdown/txt notes can carry lies, so bind to the task id (P1#1b) and require
# non-empty content. This is the weakest non-screenshot channel.
has_proof_artifact=0
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  [[ -s "$f" ]] || continue
  m=$(stat_mtime "$f")
  [[ "$m" -gt "$recent_cutoff" ]] || continue
  # Bind on a SEGMENT boundary (P2): proof under proof/T-10/ must NOT close T-1.
  # When close_task_id is empty the helper returns 0 (skip binding, demand content).
  _runecode_task_in_path "$f" "$close_task_id" || continue
  has_proof_artifact=1; break
done < <( { find ".runecode/proof" -type f \( -name '*.json' -o -name '*.md' -o -name '*.txt' \) 2>/dev/null; find "proof" -path '*/human-proof.*' -type f 2>/dev/null; } | sort -u )

# ── Evidence channel 4b: a CAPTURED, CONTENT-VALIDATED, TASK-BOUND run artifact
# PARITY with done-needs-proof (P1#2): an existence/mtime check is not enough —
# the artifact must pass _runecode_validate_artifact (real HTTP 2xx / valid ZIP /
# test-count marker / media magic) AND its path must contain the task id. An
# EMPTY proof/<task>/api.log and a "garbage" trace.zip both FAIL here.
has_run_artifact=0
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  m=$(stat_mtime "$f")
  [[ "$m" -gt "$recent_cutoff" ]] || continue
  # Bind on a SEGMENT boundary (P2): proof under proof/T-10/ must NOT close T-1.
  # When close_task_id is empty the helper returns 0 (skip binding, demand content).
  _runecode_task_in_path "$f" "$close_task_id" || continue
  if _runecode_validate_artifact "$f"; then has_run_artifact=1; break; fi
done < <(
  {
    find "proof" .runecode/proof -type f \( \
      -iname '*trace*.zip' -o -iname 'trace*.json' -o -iname '*.webm' -o \
      -iname 'maestro*' -o -iname '*.mp4' -o \
      -iname '*curl*' -o -iname '*.http' -o -iname '*status*.log' -o -iname '*.log' -o -iname 'http-status*' -o \
      -iname 'junit*.xml' -o -iname '*report*.xml' -o -iname 'results*.json' \
    \) 2>/dev/null
    find "proof" .runecode/proof -type f -path '*test-results*' 2>/dev/null
  } | sort -u
)

# ── Evidence channel 5: atlas-captures index entry, recent ───────────────────
has_atlas=0
if [[ -d ".atlas/captures" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    m=$(stat_mtime "$f")
    if [[ "$m" -gt "$recent_cutoff" ]]; then has_atlas=1; break; fi
  done < <(find ".atlas/captures" -type f -name '*.json' 2>/dev/null)
fi

# ── UI-surface escalation: a UI diff requires a screenshot or atlas capture ──
ui_pattern='\.(tsx|jsx|vue|svelte|html|css|scss|sass)$|(^|/)([Vv]iews?|[Ss]creens?|components|pages)/|.*View\.(swift|kt)$|.*Screen\.(swift|kt)$|@Composable|UIView\b|Widget\b'
has_ui_diff=0
ui_file=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if echo "$f" | grep -qE "$ui_pattern"; then has_ui_diff=1; ui_file="$f"; break; fi
done < <( { git diff --name-only HEAD 2>/dev/null; git log -10 --name-only --format='' 2>/dev/null; } | sort -u )

if [[ "$has_ui_diff" == "1" ]]; then
  if [[ "$has_recent_shot" == "1" || "$has_atlas" == "1" ]]; then exit 0; fi
  echo "" >&2
  echo "  mcp-close-guard: BLOCKED — MCP task-close touches UI surface but no recent screenshot/atlas capture." >&2
  echo "    Trigger:        $trigger_kind  (tool: $tool)" >&2
  echo "    UI file:        $ui_file" >&2
  echo "    Expected:       a screenshot in $shots_dir OR an atlas capture (mtime within last 30 min)." >&2
  echo "    Why:            closing a UI task over MCP must clear the SAME visual bar as the CLI path." >&2
  echo "    Override:       put 'runecode: allow-done --reason <text>' in the tool's note/comment field (audited)." >&2
  echo "" >&2
  exit 2
fi

if [[ "$has_recent_shot" == "1" || "$has_run_artifact" == "1" || "$has_e2e" == "1" || "$has_proof_artifact" == "1" || "$has_atlas" == "1" ]]; then
  exit 0
fi

echo "" >&2
echo "  mcp-close-guard: BLOCKED — MCP task-close with no human product-use proof." >&2
echo "    Trigger:        $trigger_kind  (tool: $tool)" >&2
echo "    Task:           ${close_task_id:-<unparsed>}" >&2
echo "    This is the structural twin of done-needs-proof for the MCP close path (P1#2 parity)." >&2
echo "    Looked for: recent screenshot / e2e-file-in-diff / content-validated + task-bound run artifact" >&2
echo "                (proof/<TASK>/ HTTP 2xx log, valid trace.zip, junit/results) / task-bound proof file" >&2
echo "                / atlas capture. A commit-message sentence is NOT proof (P1#5)." >&2
echo "    Override:       put 'runecode: allow-done --reason <text>' in the tool's note/comment field (audited)." >&2
echo "" >&2
exit 2
