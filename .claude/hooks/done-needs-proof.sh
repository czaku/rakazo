#!/usr/bin/env bash
# Rune: done-needs-proof — PreToolUse Bash hook.
# Refuses task-completion actions unless replayable evidence exists in the
# recent git history (last 10 commits) OR in PROJECT_SCREENSHOT_DIR within
# the last 30 minutes.
#
# UNIVERSAL PRINCIPLE: "Done" means a human could now exercise the feature
# through its real surface, with replayable proof. Unit tests + tsc pass
# do NOT qualify. In-process/DB-only tests do NOT satisfy E2E acceptance
# criteria. Proof is one of:
#   - a screenshot (.png/.jpg/.jpeg/.webp/.mp4/.gif) under PROJECT_SCREENSHOT_DIR
#   - an e2e/integration/journey/flow/acceptance test file in the diff
#     (works across stacks: Playwright, Cypress, XCUITest, Espresso, Detox,
#      *.e2e.ts, *e2e_test.go, test_*_e2e.py, *IntegrationTest.kt, ...)
#   - an explicit human-surface proof excerpt in a recent commit body
#     (Playwright/Cypress/Maestro/simemu/curl/API/CLI/journey proof)
#   - a recent .runecode/proof or proof/<task>/human-proof artifact
#   - an atlas-captures index entry (.atlas/captures/*.json) modified recently
#
# Surface-aware escalation: if the recent diff touches UI markers
# (HTML/JSX/Vue/Svelte/Swift View/Compose @Composable/Flutter widget/CSS),
# a screenshot or atlas capture is REQUIRED — an e2e test path alone is insufficient.
#
# Triggers:
#   - keel task update *--status done
#   - gh pr close
#   - gh issue close
#
# Override: 'runecode: allow-done --reason <text>' in the command.
# Exit 2 = block. Exit 0 = pass.

input=$(cat)
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
[[ -z "$command" ]] && exit 0

# Audit-log writer (same shape as forbidden-language / visual-proof).
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

# Determine whether this command is a "claiming done" trigger.
# Match: keel task update ... --status done | gh pr close | gh issue close
#
# P1-A (CLI bypass): keel is a commander.js CLI ('keel task update [options] <id>')
# that accepts BOTH '--status done' (space) AND '--status=done' (equals) by spec —
# a '--status[[:space:]]+done' regex only saw the space form, so '--status=done'
# exited 0 and skipped the whole gate. Every done/close trigger now tolerates the
# equals form via the '[[:space:]=]+' class (space OR '='): '--status[[:space:]=]+done'
# matches '--status done', '--status=done', and '--status  done'. Defensive short
# flag '-s done|-s=done' is matched too (harmless if keel never adds it). We also
# cover keel '--run-status done' (the run-status close form) and gh's
# '--state[[:space:]=]+closed' edit/api form, so equals/state variants can't slip the gate.
is_done_action=0
trigger_kind=""
if echo "$command" | grep -qE 'keel[[:space:]]+task[[:space:]]+update.*(--status|--run-status|-s)[[:space:]=]+done\b'; then
  is_done_action=1
  trigger_kind="keel"
elif echo "$command" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+close\b'; then
  is_done_action=1
  trigger_kind="gh-pr-close"
elif echo "$command" | grep -qE '\bgh[[:space:]]+issue[[:space:]]+close\b'; then
  is_done_action=1
  trigger_kind="gh-issue-close"
elif echo "$command" | grep -qE '\bgh[[:space:]]+(pr|issue)[[:space:]]+edit\b.*--state[[:space:]=]+closed\b'; then
  is_done_action=1
  trigger_kind="gh-state-closed"
fi

[[ "$is_done_action" == "0" ]] && exit 0

# Extract the task id being closed (P1#1b — bind proof to the task).
# 'keel task update T-123 ...' → positional id; '--id/--task/--task-id T-1' (or the
# '=' form) → the keel id. P2 (id-after-flag binding skip): the old extractor only
# grabbed the id IMMEDIATELY after 'update', so 'keel task update --status done --id T-1'
# yielded an empty id and DISABLED binding entirely. We now also read the id from any
# of --id / --task / --task-id in BOTH space and '=' forms (anywhere in the command),
# preferring an explicit flag and falling back to the positional. BSD/GNU sed safe:
# no \b (BSD sed does not support it — that silently emptied the id before).
# 'gh issue/pr close 42' / '#42' → 42. Empty only if genuinely unparseable.
close_task_id=""
close_task_id=$(echo "$command" | sed -nE 's/.*--(id|task|task-id)[[:space:]=]+([A-Za-z][A-Za-z0-9-]*[0-9]).*/\2/p' | head -1)
if [[ -z "$close_task_id" ]]; then
  close_task_id=$(echo "$command" | sed -nE 's/.*keel[[:space:]]+task[[:space:]]+update[[:space:]]+([A-Za-z][A-Za-z0-9-]*[0-9])([[:space:]].*|$)/\1/p' | head -1)
fi
if [[ -z "$close_task_id" ]]; then
  close_task_id=$(echo "$command" | sed -nE 's/.*gh[[:space:]]+(pr|issue)[[:space:]]+(close|edit)[[:space:]]+#?([0-9]+).*/\3/p' | head -1)
fi

# Override path.
if echo "$command" | grep -qE 'runecode:[[:space:]]*allow-done\b'; then
  reason=$(echo "$command" | sed -nE 's/.*runecode:[[:space:]]*allow-done[[:space:]]+--reason[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  # Reject trivial reasons — an override must carry a real, auditable justification.
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  done-needs-proof: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "    Example:      runecode: allow-done --reason 'verified login flow manually in staging, screenshot in PR #412'" >&2
    echo "" >&2
    exit 2
  fi
  _runecode_audit 'done-needs-proof' "$reason" "trigger=$trigger_kind cmd=$(echo "$command" | head -c 200)"
  _runecode_override_notify 'done-needs-proof' "$reason"
  exit 0
fi

# P1-B (fail-open seam): a real done/close trigger from a NON-git cwd must NOT be a
# free pass. The old 'git rev-parse ... || exit 0' silently exited 0 whenever proof
# could not be read — so 'keel task update T-1 --status done' from /tmp closed the
# task with zero proof. mcp-close-guard already BLOCKS this exact case; its Bash twin
# now matches: with no repo there is nothing to verify, so we BLOCK and route to the
# audited override (the override path above already ran, so a substantive
# 'runecode: allow-done --reason ...' still works here).
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "" >&2
  echo "  done-needs-proof: BLOCKED — done/close trigger ($trigger_kind) outside a git repo." >&2
  echo "    Why:      proof is read from the repo's recent diff / proof artifacts; with no repo there is" >&2
  echo "              nothing to verify, so closing here cannot be proven (P1-B: not a free pass)." >&2
  echo "    Fix:      run the close from inside the project's git working tree, OR" >&2
  echo "    Override: append 'runecode: allow-done --reason <text>' to the command (audited)." >&2
  echo "" >&2
  exit 2
fi

stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

now_epoch=$(date +%s)
recent_cutoff=$((now_epoch - 1800))  # 30 minutes

# ── Evidence channel 1: screenshot in PROJECT_SCREENSHOT_DIR, recent ────────
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
shots_dir="${PROJECT_SCREENSHOT_DIR:-$HOME/Desktop/screenshots/$project}"
has_recent_shot=0
newest_shot_path=""
if [[ -d "$shots_dir" ]]; then
  while IFS= read -r shot; do
    [[ -f "$shot" ]] || continue
    m=$(stat_mtime "$shot")
    if [[ "$m" -gt "$recent_cutoff" ]]; then
      has_recent_shot=1
      newest_shot_path="$shot"
      break
    fi
  done < <(find "$shots_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o -name '*.mp4' -o -name '*.gif' \) 2>/dev/null)
fi

# ── Evidence channel 2: e2e/integration/journey/flow/acceptance test in diff ─
# Universal patterns spanning Playwright, Cypress, XCUITest, Espresso, Detox,
# Go, Python, Ruby, etc.
#
# HARDENED (Fix #3): an e2e test FILE PATH alone is the WEAKEST signal — a stale
# e2e file from 9 commits ago, or an empty new test, "proves" nothing ran. So we
# now only count e2e files that are in THIS change set (uncommitted working tree
# OR the single most-recent commit), NOT anywhere in the last 10 commits. And
# even then, a captured RUN ARTIFACT (channel 4b) is what actually proves the
# E2E executed — see has_run_artifact below.
e2e_pattern='(e2e|E2E|integration|Integration|journey|Journey|flow|Flow|acceptance|Acceptance|ui-test|UITest|xcuitest|XCUITest|espresso|Espresso|detox|Detox|playwright|Playwright|cypress|Cypress|webdriver|WebDriver)'
has_e2e=0
e2e_file=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if echo "$f" | grep -qE "$e2e_pattern"; then
    has_e2e=1
    e2e_file="$f"
    break
  fi
done < <(
  {
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
    git show --name-only --format='' HEAD 2>/dev/null
  } | sort -u
)

# ── Evidence channel 3: REMOVED (P1#5) ──────────────────────────────────────
# A commit-body text claim ("curl API returned HTTP 200", "journey passed") is
# NOT proof — it's a sentence anyone can type. The previous has_human_output
# channel let pure prose satisfy the gate, undercutting the run-artifact check.
# Prose is not proof: a real claim must be backed by an artifact (channel 4 /
# 4b), an e2e file in THIS change set (channel 2), a screenshot, or an atlas
# capture. This channel is intentionally gone.

# ── Evidence channel 4: explicit proof artifact, recent + task-bound ─────────
# A human-proof file is a deliberate artifact, but it must (a) be recent and
# (b) reference the task being closed (P1#1b) — a proof file for another task
# does not close THIS one. Markdown/txt notes can still carry lies, so this is
# the weakest non-screenshot channel; binding limits the blast radius.
has_proof_artifact=0
proof_artifact=""
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  [[ -s "$f" ]] || continue
  m=$(stat_mtime "$f")
  [[ "$m" -gt "$recent_cutoff" ]] || continue
  # Bind on a SEGMENT boundary (P2): proof under proof/T-10/ must NOT close T-1.
  # When close_task_id is empty the helper returns 0 (skip binding, demand content).
  _runecode_task_in_path "$f" "$close_task_id" || continue
  has_proof_artifact=1
  proof_artifact="$f"
  break
done < <(
  {
    find ".runecode/proof" -type f \( -name '*.json' -o -name '*.md' -o -name '*.txt' \) 2>/dev/null
    find "proof" -path '*/human-proof.*' -type f 2>/dev/null
  } | sort -u
)

# ── Evidence channel 4b: a CAPTURED E2E RUN ARTIFACT under proof/ (Fix #3) ───
# This is the strong "the test actually RAN" signal — not a file path, but the
# OUTPUT of a run. Recognised artifacts (recent, under proof/** or
# .runecode/proof/**), named by the runner:
#   - Playwright: trace.zip, *trace*.zip, *trace*.json, *.webm, test-results/**
#   - Maestro:    maestro-*.{mp4,xml,json}, *maestro*/**
#   - curl/HTTP:  *curl*, *.http, *status*.log, http-status*.txt (a status log)
#   - JUnit/run:  junit*.xml, *report*.xml, results*.json (a results report)
# An e2e test FILE without one of these is downgraded — see the decision table.
#
# HARDENED (P1#1): existence + recency is NOT enough. Each candidate must (a) pass
# _runecode_validate_artifact (real content: HTTP 2xx line / valid ZIP / test-count
# marker / media magic — an EMPTY log or a "garbage not a real trace" .zip FAILS),
# and (b) be BOUND to the task being closed — its path must contain $close_task_id
# (e.g. proof/<TASK>/...), so proof/<other-task>/... does NOT close <TASK>. When the
# task id can't be parsed we skip the binding check but still demand real content.
has_run_artifact=0
run_artifact=""
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  m=$(stat_mtime "$f")
  [[ "$m" -gt "$recent_cutoff" ]] || continue
  # Bind to the task id (P1#1b): the artifact path must reference this task.
  # Bind on a SEGMENT boundary (P2): proof under proof/T-10/ must NOT close T-1.
  # When close_task_id is empty the helper returns 0 (skip binding, demand content).
  _runecode_task_in_path "$f" "$close_task_id" || continue
  # Validate content (P1#1a): empty / garbage artifacts do not count.
  if _runecode_validate_artifact "$f"; then
    has_run_artifact=1
    run_artifact="$f"
    break
  fi
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
# Atlas writes JSON capture artifacts to .atlas/captures/*.json with provenance.
has_atlas=0
atlas_file=""
if [[ -d ".atlas/captures" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    m=$(stat_mtime "$f")
    if [[ "$m" -gt "$recent_cutoff" ]]; then
      has_atlas=1
      atlas_file="$f"
      break
    fi
  done < <(find ".atlas/captures" -type f -name '*.json' 2>/dev/null)
fi

# ── Surface-aware escalation: UI markers in the recent diff ─────────────────
# If UI surface was touched, a SCREENSHOT (or atlas capture) is required —
# e2e file alone or human-output alone is insufficient.
ui_pattern='\.(tsx|jsx|vue|svelte|html|css|scss|sass)$|(^|/)([Vv]iews?|[Ss]creens?|components|pages)/|.*View\.(swift|kt)$|.*Screen\.(swift|kt)$|@Composable|UIView\b|Widget\b'
has_ui_diff=0
ui_file=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if echo "$f" | grep -qE "$ui_pattern"; then
    has_ui_diff=1
    ui_file="$f"
    break
  fi
done < <(
  {
    git diff --name-only HEAD 2>/dev/null
    git log -10 --name-only --format='' 2>/dev/null
  } | sort -u
)

# Decision table.
if [[ "$has_ui_diff" == "1" ]]; then
  # UI surface — require screenshot or atlas capture.
  if [[ "$has_recent_shot" == "1" || "$has_atlas" == "1" ]]; then
    exit 0
  fi
  echo "" >&2
  echo "  done-needs-proof: BLOCKED — task touches UI surface but no recent screenshot/atlas capture." >&2
  echo "    Trigger:        $trigger_kind" >&2
  echo "    UI file:        $ui_file" >&2
  echo "    Expected:       a screenshot in $shots_dir (mtime within last 30 min)" >&2
  echo "                    OR an atlas capture in .atlas/captures/ (mtime within last 30 min)" >&2
  echo "    Why:            E2E test paths and human-output text alone don't prove visual correctness." >&2
  echo "    Override:       append 'runecode: allow-done --reason <text>' to the command (audited)." >&2
  echo "" >&2
  exit 2
fi

# Non-UI surface — require a user-surface proof channel, not just generic tests.
# A captured RUN ARTIFACT (has_run_artifact, content-validated + task-bound) is
# the strongest signal that the E2E actually executed; an e2e file freshly in
# THIS change set, a screenshot, a task-bound proof file, or an atlas capture
# also pass. A commit-body text claim alone does NOT pass (P1#5 — prose is not
# proof).
if [[ "$has_recent_shot" == "1" || "$has_run_artifact" == "1" || "$has_e2e" == "1" || "$has_proof_artifact" == "1" || "$has_atlas" == "1" ]]; then
  exit 0
fi

echo "" >&2
echo "  done-needs-proof: BLOCKED — no human product-use proof found before marking done." >&2
echo "    Trigger:        $trigger_kind" >&2
echo "    Task:           ${close_task_id:-<unparsed>}" >&2
echo "    Looked for ANY of:" >&2
echo "      - screenshot:   $shots_dir/*.{png,jpg,jpeg,webp,mp4,gif} (mtime within last 30 min)" >&2
echo "      - run artifact: proof/<TASK>/ (Playwright trace.zip/*.webm, Maestro *.mp4/xml, curl/http-status log," >&2
echo "                      junit/results report) — must be NON-EMPTY, have real content (HTTP 2xx / valid ZIP /" >&2
echo "                      test-count marker), and its path must contain the task id being closed" >&2
echo "      - e2e file:     a $e2e_pattern path in THIS change set (working tree or HEAD commit only)" >&2
echo "      - proof file:   .runecode/proof/* or proof/*/human-proof.* (recent, referencing this task)" >&2
echo "      - atlas:        .atlas/captures/*.json (mtime within last 30 min)" >&2
echo "    Why:            \"Done\" means a human could exercise the feature through its real surface." >&2
echo "                    Unit tests + tsc pass do NOT qualify. A stale e2e file path does NOT prove a run." >&2
echo "                    A commit-message sentence is NOT proof (P1#5). Capture the RUN OUTPUT:" >&2
echo "                    e.g. curl -i ... | tee proof/${close_task_id:-T-1}/api.log  (must show 'HTTP/.. 2xx')." >&2
echo "    Override:       append 'runecode: allow-done --reason <text>' to the command (audited)." >&2
echo "" >&2
exit 2
