#!/usr/bin/env bash
# Rune: cwd-guard — PreToolUse Write/Edit hook.
# Blocks writes to files outside the current working directory.
# Catches "wrong dir" / "wrong project" errors — in 4/8 projects Claude
# wrote files into a different project than the one it was asked to work in.
# Exit code 2 = block + message.

input=$(cat)
file=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); ti=d.get('tool_input', d.get('input', {})); print(ti.get('file_path', ti.get('path', '')))" 2>/dev/null)

[[ -z "$file" ]] && exit 0

# Resolve the file path to an absolute path
case "$file" in
  /*) abs_file="$file" ;;
  ~*) abs_file="${HOME}${file#~}" ;;
  *)  abs_file="${PWD}/${file}" ;;
esac

# Resolve CWD to an absolute path (follow symlinks)
abs_cwd=$(pwd -P 2>/dev/null || pwd)

# Normalise both paths
abs_file=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$abs_file" 2>/dev/null || echo "$abs_file")
abs_cwd=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$abs_cwd" 2>/dev/null || echo "$abs_cwd")

# Allow writes inside CWD
case "$abs_file" in
  "${abs_cwd}/"*) exit 0 ;;
  "$abs_cwd")      exit 0 ;;
esac

# Allow writes to ~/.claude (hooks, settings, CLAUDE.md — legitimate global config)
case "$abs_file" in
  "${HOME}/.claude/"*) exit 0 ;;
esac

# Allow writes to the kimi-code home ($KIMI_CODE_HOME, default ~/.kimi-code) —
# AGENTS.md, config.toml, skills/ and hooks/ are legitimate global config.
_rc_kimi_home="${KIMI_CODE_HOME:-${HOME}/.kimi-code}"
case "$abs_file" in
  "${_rc_kimi_home}/"*) exit 0 ;;
esac

# Allow writes to /tmp (screenshots, temp files)
case "$abs_file" in
  /tmp/*) exit 0 ;;
  /var/folders/*) exit 0 ;;
esac

echo "" >&2
echo "  cwd-guard: BLOCKED — file is outside the current project directory." >&2
echo "" >&2
echo "    Writing to: $abs_file" >&2
echo "    CWD:        $abs_cwd" >&2
echo "" >&2
echo "  Are you in the wrong project? Verify with: pwd" >&2
echo "  If this write is intentional, cd to the correct directory first." >&2
echo "" >&2
exit 2
