#!/usr/bin/env bash
# Rune: visual-proof — Stop hook.
# Refuses session stop if any UI file has been edited in the working tree
# AND no screenshot exists in PROJECT_SCREENSHOT_DIR newer than the file's mtime.
#
# UI patterns: views/**, Views/**, screens/**, Screens/**, components/**, pages/**,
#   *View.swift, *Screen.swift, *View.kt, *Screen.kt, *.tsx, *.jsx (component-ish only)
#
# Override: HEAD commit message contains 'runecode: ui-skip-screenshot --reason <text>'.
# Exit 2 = block. Exit 0 = pass.

# Only in git repos
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

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

# Override via HEAD commit message
head_msg=$(git log -1 --format='%B' 2>/dev/null)
if echo "$head_msg" | grep -qE 'runecode:[[:space:]]*ui-skip-screenshot\b'; then
  # Sed's '.' doesn't match newlines, so the capture is naturally line-bounded.
  # Allows '#' (issue refs) inside the reason text.
  reason=$(echo "$head_msg" | sed -nE 's/.*runecode:[[:space:]]*ui-skip-screenshot[[:space:]]+--reason[[:space:]]+(.{1,200}).*/\1/p' | head -1)
  [[ -z "$reason" ]] && reason='(no reason given)'
  # Reject trivial reasons — a VISUAL override must carry a real justification.
  if ! _runecode_reason_ok "$reason"; then
    echo "" >&2
    echo "  visual-proof: OVERRIDE REJECTED — reason is trivial or missing." >&2
    echo "    Reason given: '$reason'" >&2
    echo "    Required:     a substantive reason (>= 15 meaningful chars; not 'test'/empty/'(no reason given)')." >&2
    echo "" >&2
    exit 2
  fi
  head_sha=$(git rev-parse --short HEAD 2>/dev/null)
  _runecode_audit 'visual-proof' "$reason" "HEAD=$head_sha"
  _runecode_override_notify 'visual-proof' "$reason"
  exit 0
fi

# Find UI files modified in the working tree (uncommitted) and recently committed.
# We use combined: working-tree changes + last 5 commits (this session's window).
# Use NUL-delimited paths so filenames with spaces/newlines are handled correctly.
ui_pattern='(^|/)([Vv]iews?|[Ss]creens?|components|pages)/|.*View\.(swift|kt|tsx|jsx)$|.*Screen\.(swift|kt|tsx|jsx)$|.*Component\.(tsx|jsx)$'

stat_mtime() {
  # Nanosecond precision (portable via python3) so the pHash baseline watermark
  # distinguishes sub-second consecutive UI edits — whole-second mtimes would let
  # a same-second re-edit skip the drift comparison. Falls back to whole seconds.
  python3 -c "import os, sys
try:
    print(os.stat(sys.argv[1]).st_mtime_ns)
except OSError:
    print(0)" "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

newest_ui=0
newest_ui_file=""
have_ui=0
ui_files=()
while IFS= read -r -d '' f; do
  echo "$f" | grep -qE "$ui_pattern" || continue
  # Exclude keel-generated views/*.md — the REPO-ROOT views/ dir holds generated
  # task/roadmap summaries (markdown), not UI source. Root-anchored (^views/) on
  # purpose: a nested src/views/*.md could be real UI docs, so only the top-level
  # keel render dir is exempt. SwiftUI Views/*.swift (capital V, .swift) still
  # trips the gate. Without this, keel render churn false-fires the visual-proof
  # Stop hook and forces spurious overrides.
  echo "$f" | grep -qE '^views/[^/]+\.md$' && continue
  have_ui=1
  [[ -f "$f" ]] || continue
  m=$(stat_mtime "$f")
  ui_files+=("$f")
  if [[ "$m" -gt "$newest_ui" ]]; then
    newest_ui=$m
    newest_ui_file="$f"
  fi
done < <(
  {
    git diff -z --name-only HEAD 2>/dev/null
    git ls-files -z --others --exclude-standard 2>/dev/null
    git log -5 -z --name-only --format='' 2>/dev/null
  }
)

[[ "$have_ui" == 0 ]] && exit 0

# No real UI files on disk — likely deletes; skip
[[ "$newest_ui" == 0 ]] && exit 0

# Resolve screenshot dir: PROJECT_SCREENSHOT_DIR or default ~/Desktop/screenshots/<project>
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
shots_dir="${PROJECT_SCREENSHOT_DIR:-$HOME/Desktop/screenshots/$project}"

if [[ ! -d "$shots_dir" ]]; then
  echo "" >&2
  echo "  visual-proof: BLOCKED — UI files were edited but no screenshot directory exists." >&2
  echo "    UI file:        $newest_ui_file" >&2
  echo "    Expected dir:   $shots_dir" >&2
  echo "    Fix:            mkdir -p \"$shots_dir\" && screenshot the change." >&2
  echo "    Override:       include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  echo "" >&2
  exit 2
fi

# Find newest screenshot mtime
newest_shot=0
newest_shot_path=""
while IFS= read -r shot; do
  [[ -f "$shot" ]] || continue
  m=$(stat_mtime "$shot")
  if [[ "$m" -gt "$newest_shot" ]]; then
    newest_shot=$m
    newest_shot_path="$shot"
  fi
done < <(find "$shots_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) 2>/dev/null)

if [[ "$newest_shot" == 0 ]]; then
  echo "" >&2
  echo "  visual-proof: BLOCKED — UI files edited but $shots_dir has no screenshots." >&2
  echo "    UI file:   $newest_ui_file" >&2
  echo "    Override:  include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  echo "" >&2
  exit 2
fi

# ── T-LU-302: per-surface screenshot matching ────────────────────────────────
# Every edited UI file must be covered by proof for ITS surface:
#   (a) tagged proof — a screenshot whose filename contains the file's surface
#       tag (case-insensitive) and is newer than the edit; OR
#   (b) global fallback — any screenshot at least as new as the edit (the
#       pre-T-LU-302 newest-vs-newest rule), so existing workflows and
#       untaggable files stay fail-closed instead of breaking.
# A file with no derivable tag goes straight to (b).
surface_tags() {
  # Surface tag: basename without extension, lowercased, common suffixes
  # stripped (View|Screen|Page|Component) — e.g. BodyPhotoOverlayView.swift →
  # bodyphotooverlay, TodayPage.tsx → today, ChatFeed.swift → chatfeed.
  # Plus a parent-dir surface when the parent is a known surface-ish name.
  local base tag parent
  base=$(basename "$1")
  base="${base%.*}"
  tag=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -E 's/(view|screen|page|component)$//' | sed -E 's/[^a-z0-9_-]+//g')
  [[ -n "$tag" ]] && printf '%s ' "$tag"
  parent=$(basename "$(dirname "$1")" | tr '[:upper:]' '[:lower:]')
  case "$parent" in
    body|chat|today|plans|goals|settings|photos) printf '%s ' "$parent" ;;
  esac
}

unsatisfied=()
for uf in "${ui_files[@]}"; do
  uf_mtime=$(stat_mtime "$uf")
  uf_ok=0
  for tag in $(surface_tags "$uf"); do
    while IFS= read -r shot; do
      [[ -f "$shot" ]] || continue
      sm=$(stat_mtime "$shot")
      if (( sm > uf_mtime )); then
        uf_ok=1
        break
      fi
    done < <(find "$shots_dir" -type f -iname "*${tag}*" \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null)
    [[ "$uf_ok" == 1 ]] && break
  done
  # Global fallback (pre-T-LU-302 rule): any screenshot at least as new as the edit.
  if [[ "$uf_ok" == 0 ]] && (( newest_shot >= uf_mtime )); then
    uf_ok=1
  fi
  [[ "$uf_ok" == 0 ]] && unsatisfied+=("$uf")
done

if [[ ${#unsatisfied[@]} -gt 0 ]]; then
  echo "" >&2
  echo "  visual-proof: BLOCKED — edited UI surface(s) without a fresh screenshot:" >&2
  for uf in "${unsatisfied[@]}"; do
    uf_tags=$(surface_tags "$uf" | sed 's/ *$//')
    if [[ -n "$uf_tags" ]]; then
      echo "    ✗ $uf (surface: $uf_tags — need a newer screenshot matching the surface, or any newer screenshot)" >&2
    else
      echo "    ✗ $uf (need any screenshot newer than the edit)" >&2
    fi
  done
  echo "    Shots dir:  $shots_dir" >&2
  echo "    Fix:        screenshot each changed surface before declaring done." >&2
  echo "    Override:   include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  echo "" >&2
  exit 2
fi

# ── T-LU-182: perceptual-hash baseline drift gate ───────────────────────────
# A genuine UI change must shift the screenshot's 64-bit average-hash from the
# stored pre-edit baseline by at least `min_bits` (a fraction of 64). Below
# that, the screenshot is a re-rendered identical screen (anti-AI-slop) and the
# hook blocks. threshold resolves: env override > runecode.yaml > default 0.05.
# Resolve threshold: env override > runecode.yaml > default 0.05. A threshold
# that is PRESENT but not a finite number in (0, 1] prints INVALID so the hook
# fails closed rather than silently using the default (which would lower the
# gate). Matches the runecode-config.ts validator's contract.
vp_threshold=$(RUNECODE_VP_ENV="${RUNECODE_VISUAL_PROOF_THRESHOLD:-}" python3 - <<'PY'
import os, re
def valid(x):
    # Mirrors runecode-config.ts: a bare finite number in (0, 1]. A quoted
    # scalar (YAML string) or any junk ⇒ None ⇒ caller fails closed.
    try:
        f = float(x)
    except (TypeError, ValueError):
        return None
    return f if 0 < f <= 1 else None
def from_env():
    raw = os.environ.get('RUNECODE_VP_ENV', '').strip()
    if raw == '':
        return ('absent', None)
    v = valid(raw)
    return ('ok', v) if v is not None else ('invalid', None)
def from_yaml():
    for fn in ('runecode.yaml',):
        try:
            text = open(fn).read()
        except OSError:
            continue
        # flow style: visual_proof: { threshold: <scalar> }. Once the block is
        # found it is authoritative — mirror pickVisualProof in runecode-config:
        # 'threshold' is required, no other keys are allowed, and the value must
        # be a number in (0, 1]. Anything else fails closed (never silent default).
        fm = re.search(r'(?m)^visual_proof:[ \t]*\{([^}\n]*)\}[ \t]*(?:#.*)?$', text)
        if fm:
            inner = fm.group(1)
            keys = re.findall(r'([A-Za-z_][A-Za-z0-9_]*)[ \t]*:', inner)
            if any(k != 'threshold' for k in keys):
                return ('invalid', None)
            km = re.search(r'threshold:[ \t]*([^,}#]*)', inner)
            if km is None:
                return ('invalid', None)
            v = valid(km.group(1).strip())
            return ('ok', v) if v is not None else ('invalid', None)
        # visual_proof present with a non-object value (null, a bare number, a
        # sequence, true, ...). pickVisualProof requires an object → fail closed
        # rather than silently fall back to the default threshold.
        sm = re.search(r'(?m)^visual_proof:[ \t]+(\S.*?)[ \t]*(?:#.*)?$', text)
        if sm:
            return ('invalid', None)
        # block style: visual_proof:\n  threshold: <scalar>
        bm = re.search(r'(?m)^visual_proof:[ \t]*(?:#.*)?$', text)
        if not bm:
            continue
        found = None
        for line in text[bm.end():].splitlines():
            if line.strip() == '':
                continue
            if not line[:1].isspace():
                break  # dedent → left the visual_proof block
            km = re.match(r'[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:[ \t]*([^#\n]*?)[ \t]*(?:#.*)?$', line)
            if km is None:
                continue
            if km.group(1) != 'threshold':
                return ('invalid', None)  # unknown key
            found = valid(km.group(2).strip())
        return ('ok', found) if found is not None else ('invalid', None)
    return ('absent', None)
state, val = from_env()
if state == 'absent':
    state, val = from_yaml()
print('INVALID' if state == 'invalid' else (val if state == 'ok' else 0.05))
PY
)
if [[ "$vp_threshold" == INVALID ]]; then
  echo "" >&2
  echo "  visual-proof: BLOCKED — visual_proof.threshold is set but is not a number in (0, 1]." >&2
  echo "    Fix:      set visual_proof.threshold to a fraction such as 0.05 (5% of the 64-bit pHash)." >&2
  echo "    Override: include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  echo "" >&2
  exit 2
fi
vp_min_bits=$(python3 -c "import math, sys
t = float(sys.argv[1])
print(max(1, math.ceil(t * 64)))" "$vp_threshold" 2>/dev/null || echo 4)

# Per-repo baseline store path. The baseline is read + compared + rewritten
# inside the Python validator below using symlink-safe syscalls.
vp_state_dir="${RUNECODE_STATE_HOME:-$HOME/.runecode}/visual-baseline"
vp_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
# Bind the baseline to the proof SURFACE (repo + the UI file being edited), not
# the repo alone — otherwise an unchanged screenshot for screen A could be
# compared against an unrelated screen B's baseline and pass.
vp_surface="$vp_root::$newest_ui_file"
vp_key=$(printf '%s' "$vp_surface" | shasum -a 256 2>/dev/null | cut -c1-40)
[[ -z "$vp_key" ]] && vp_key=$(printf '%s' "$vp_surface" | cksum | tr -d ' ')
vp_baseline_file="$vp_state_dir/$vp_key.phash"

visual_check_json=$(SCREENSHOT_PATH="$newest_shot_path" EXPECTED_MTIME="$newest_ui" \
  BASELINE_FILE="$vp_baseline_file" NEWEST_UI="$newest_ui" MIN_BITS="$vp_min_bits" python3 - <<'PY'
import base64
import hashlib
import json
import os
import re
import struct
import sys
import tempfile
import zlib

path = os.environ.get('SCREENSHOT_PATH', '')
expected_mtime = int(os.environ.get('EXPECTED_MTIME', '0') or '0')
baseline_file = os.environ.get('BASELINE_FILE', '')
def _int_env(name):
    try:
        return int(os.environ.get(name, '0') or '0')
    except ValueError:
        return 0
newest_ui = _int_env('NEWEST_UI')
min_bits = _int_env('MIN_BITS') or 3
errors = []

PHASH_RE = re.compile(r'^[0-9a-f]{16}$')

def read_baseline(p):
    # (phash, ui_mtime) or (None, None) if absent. Raises ValueError if present
    # but malformed/symlinked — fail closed, never silently disable the gate.
    if not p:
        return (None, None)
    try:
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return (None, None)
    except OSError:
        raise ValueError('baseline-invalid')  # ELOOP (symlink) or unreadable
    try:
        raw = os.read(fd, 4096).decode('utf-8', 'replace')
    finally:
        os.close(fd)
    # Require EXACTLY '<16-hex-phash> <non-negative-int-mtime>'. A phash-only
    # record, a non-numeric watermark, or extra fields is corruption → fail
    # closed rather than silently degrade to mtime 0 (which would re-enable or
    # disable the gate unpredictably).
    parts = raw.split(chr(10), 1)[0].split()
    if len(parts) != 2 or not PHASH_RE.match(parts[0]):
        raise ValueError('baseline-invalid')
    try:
        mt = int(parts[1])
    except ValueError:
        raise ValueError('baseline-invalid')
    if mt < 0:
        raise ValueError('baseline-invalid')
    return (parts[0], mt)

def write_baseline(p, phash, ui_mtime):
    d = os.path.dirname(p) or '.'
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix='.phash-')
    try:
        os.write(fd, ('%s %d%s' % (phash, ui_mtime, chr(10))).encode('utf-8'))
        os.close(fd)
        os.replace(tmp, p)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

def fail(reason):
    errors.append(reason)

def decode_png(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not-png')
    pos = 8
    width = height = bit_depth = color_type = None
    idat = []
    while pos + 12 <= len(data):
        length = struct.unpack('>I', data[pos:pos+4])[0]
        ctype = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+length]
        pos += 12 + length
        if pos > len(data):
            raise ValueError('truncated-png')
        if ctype == b'IHDR':
            width, height = struct.unpack('>II', chunk[:8])
            bit_depth = chunk[8]
            color_type = chunk[9]
            if chunk[12] != 0:
                raise ValueError('interlaced-png')
        elif ctype == b'IDAT':
            idat.append(chunk)
        elif ctype == b'IEND':
            break
    if not width or not height or bit_depth != 8 or not idat:
        raise ValueError('unsupported-png')
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError('unsupported-color-type')
    raw = zlib.decompress(b''.join(idat))
    stride = width * channels
    if len(raw) < height * (stride + 1):
        raise ValueError('truncated-pixels')
    pixels = bytearray(width * height * 4)
    prev = bytearray(stride)
    off = 0
    for y in range(height):
        filt = raw[off]
        off += 1
        line = bytearray(raw[off:off+stride])
        off += stride
        for i in range(len(line)):
            left = line[i - channels] if i >= channels else 0
            up = prev[i] if i < len(prev) else 0
            ul = prev[i - channels] if i >= channels and i - channels < len(prev) else 0
            if filt == 1:
                line[i] = (line[i] + left) & 255
            elif filt == 2:
                line[i] = (line[i] + up) & 255
            elif filt == 3:
                line[i] = (line[i] + ((left + up) // 2)) & 255
            elif filt == 4:
                p = left + up - ul
                pa, pb, pc = abs(p-left), abs(p-up), abs(p-ul)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else ul)) & 255
            elif filt != 0:
                raise ValueError('unknown-png-filter')
        for x in range(width):
            src = x * channels
            dst = (y * width + x) * 4
            if color_type == 0:
                g = line[src]
                pixels[dst:dst+4] = bytes([g, g, g, 255])
            elif color_type == 2:
                pixels[dst:dst+4] = bytes([line[src], line[src+1], line[src+2], 255])
            elif color_type == 4:
                g = line[src]
                pixels[dst:dst+4] = bytes([g, g, g, line[src+1]])
            else:
                pixels[dst:dst+4] = bytes(line[src:src+4])
        prev = line
    return width, height, bytes(pixels)

def avg_hash(width, height, pixels):
    samples = []
    for y in range(8):
        for x in range(8):
            sx = min(width - 1, int((x + 0.5) * width / 8))
            sy = min(height - 1, int((y + 0.5) * height / 8))
            off = (sy * width + sx) * 4
            samples.append(0.299 * pixels[off] + 0.587 * pixels[off+1] + 0.114 * pixels[off+2])
    avg = sum(samples) / len(samples)
    bits = ''.join('1' if s >= avg else '0' for s in samples)
    return f'{int(bits, 2):016x}'

result = {
    'ok': False,
    'kind': 'visual-proof',
    'verdict': 'visual-invalid',
    'artifact': {
        'path': path,
        'exists': False,
        'bytes': None,
        'sha256': None,
        'width': None,
        'height': None,
        'pHash': None,
        'blank': None,
        'mtime': None,
    },
    'failures': [],
    'replayCommand': 'runecode visual-proof hook',
}

phash = None
base_phash = None
base_mtime = None
try:
    st = os.stat(path)
    data = open(path, 'rb').read()
    result['artifact'].update({
        'exists': True,
        'bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'mtime': int(st.st_mtime),
    })
    if len(data) < 1024:
        fail('tiny-image')
    # expected_mtime (NEWEST_UI) is nanoseconds — compare like-for-like.
    if st.st_mtime_ns < expected_mtime:
        fail('stale-image')
    width, height, pixels = decode_png(data)
    phash = avg_hash(width, height, pixels)
    first = pixels[:4]
    blank = all(pixels[i:i+4] == first for i in range(0, len(pixels), 4))
    result['artifact'].update({'width': width, 'height': height, 'pHash': phash, 'blank': blank})
    result['artifact']['minBits'] = min_bits
    if width < 16 or height < 16:
        fail('tiny-image')
    if blank:
        fail('blank-image')
    # T-LU-182: drift vs the pre-edit baseline. A malformed/symlinked baseline
    # fails CLOSED (baseline-invalid) — never silently disables the gate. The
    # drift check applies ONLY when the UI was edited since the baseline was
    # accepted (newest_ui > stored mtime); otherwise a no-edit Stop would
    # compare the screenshot to itself and falsely block. After a real edit, an
    # identical re-render (drift < min_bits) is AI-slop, not proof.
    try:
        base_phash, base_mtime = read_baseline(baseline_file)
    except ValueError:
        base_phash = None
        fail('baseline-invalid')
    result['artifact']['baselinePHash'] = base_phash
    if base_phash is not None and PHASH_RE.match(phash):
        if base_mtime > newest_ui:
            # Watermark newer than the current UI edit ⇒ corrupt/clock-skewed.
            # Fail closed instead of silently skipping the drift comparison.
            fail('baseline-invalid')
        elif newest_ui > base_mtime:
            drift = bin(int(phash, 16) ^ int(base_phash, 16)).count('1')
            result['artifact']['drift'] = drift
            if drift < min_bits:
                fail('unchanged-screen')
        # base_mtime == newest_ui ⇒ no new edit since acceptance ⇒ skip drift.
except Exception as exc:
    fail('corrupt-image')
    result['artifact']['error'] = exc.__class__.__name__

# T-LU-182: persist the accepted screenshot as the new baseline — but ONLY on a
# clean pass AND when this is a first proof or a genuine new edit. Fail closed
# if the write fails, so the next identical re-render cannot slip through on a
# missing baseline.
if not errors and phash and (base_phash is None or newest_ui > base_mtime):
    try:
        write_baseline(baseline_file, phash, newest_ui)
    except OSError:
        fail('baseline-write-failed')

result['failures'] = [{'field': 'artifact', 'reason': e, 'errorClass': 'visual-invalid'} for e in sorted(set(errors))]
result['ok'] = not result['failures']
result['verdict'] = 'PASS' if result['ok'] else 'visual-invalid'
print(json.dumps(result, sort_keys=True))
PY
)

if [[ "$RUNECODE_HOOK_JSON" == "1" ]]; then
  echo "$visual_check_json"
fi

visual_ok=$(echo "$visual_check_json" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin).get("ok") else "0")' 2>/dev/null || echo 0)
if [[ "$visual_ok" != "1" ]]; then
  reasons=$(echo "$visual_check_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(", ".join(f.get("reason","unknown") for f in d.get("failures", [])))' 2>/dev/null || echo "visual-invalid")
  echo "" >&2
  if [[ "$reasons" == *unchanged-screen* ]]; then
    # T-LU-182: the screenshot is a re-rendered identical screen — not proof.
    cur_drift=$(echo "$visual_check_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["artifact"].get("drift",""))' 2>/dev/null)
    echo "  visual-proof: BLOCKED — screenshot is visually identical to the pre-edit baseline." >&2
    echo "    Screenshot:     $newest_shot_path" >&2
    echo "    pHash drift:    ${cur_drift:-0}/64 bits changed (need >= $vp_min_bits)" >&2
    echo "    Meaning:        the UI did not visibly change — re-rendering the same" >&2
    echo "                    screen is not proof. Capture the ACTUAL changed state." >&2
    echo "    Tune:           set visual_proof.threshold in runecode.yaml (fraction of 64)." >&2
    echo "    Override:       include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  else
    echo "  visual-proof: BLOCKED — screenshot artifact failed image validation." >&2
    echo "    Screenshot:     $newest_shot_path" >&2
    echo "    Reason:         $reasons" >&2
    echo "    Required:       nonblank PNG, >=1024 bytes, >=16x16, decodable dimensions, pHash metadata." >&2
    echo "    Fix:            capture a real screenshot of the changed UI." >&2
    echo "    Override:       include 'runecode: ui-skip-screenshot --reason <text>' in the HEAD commit message." >&2
  fi
  echo "" >&2
  exit 2
fi

# Baseline persistence is handled atomically + symlink-safely inside the Python
# validator above (and fails closed via baseline-write-failed if it cannot write).
exit 0
