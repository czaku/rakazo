#!/usr/bin/env bash
# Rune: plays a sound when Claude finishes a response.
# DEBOUNCED: with an agent team, every teammate fires Stop on every turn — a bare
# afplay then rings N times at once (a "choir"). An atomic mkdir lock lets exactly
# ONE racer ring per debounce window; the rest exit silently.
# Opt out entirely: export RUNECODE_NO_NOTIFY=1
[[ -n "$RUNECODE_NO_NOTIFY" ]] && exit 0
_rc_lock="${TMPDIR:-/tmp}/runecode-notify.lock.d"
# Crash-orphan recovery: drop a lock older than 30s (portable mtime via stat).
if [[ -d "$_rc_lock" ]]; then
  _m=$(stat -f %m "$_rc_lock" 2>/dev/null || stat -c %Y "$_rc_lock" 2>/dev/null || echo 0)
  (( $(date +%s) - _m > 30 )) && rmdir "$_rc_lock" 2>/dev/null
fi
# mkdir is atomic: only the first of N concurrent agents wins; the rest skip.
mkdir "$_rc_lock" 2>/dev/null || exit 0
# Reopen the window after the debounce period, detached so the hook returns now.
( sleep 4; rmdir "$_rc_lock" 2>/dev/null ) >/dev/null 2>&1 &
disown 2>/dev/null || true
afplay /System/Library/Sounds/Glass.aiff >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
