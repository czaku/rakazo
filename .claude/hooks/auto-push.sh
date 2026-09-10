#!/usr/bin/env bash
# Rune: auto-push — PostToolUse Bash hook.
# If a git commit just succeeded, push immediately.
# Eliminates the 31% of sessions where work is committed but never pushed.

input=$(cat)

# Only trigger after Bash tool calls
tool=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null)
[[ "$tool" == "Bash" ]] || exit 0

# Check exit code — only trigger on successful commands
exit_code=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('exit_code', d.get('exitCode', 1)))" 2>/dev/null)
[[ "$exit_code" == "0" ]] || exit 0

# Only trigger when the command was a git commit
command=$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input', d.get('input', {})).get('command', ''))" 2>/dev/null)
echo "$command" | grep -qE '^git commit' || exit 0

# Must be in a git repo with a remote
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
remote=$(git remote | head -1)
[[ -z "$remote" ]] && exit 0

# Get current branch
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -z "$branch" ]] || [[ "$branch" == "HEAD" ]]; then
  exit 0
fi

# Never auto-push straight to main. main only advances through the
# operator's reviewed merge stage (AGENTS.md: independent second-engine
# review is a hard gate, and a lane never self-pushes to the integration
# branch). Auto-pushing a lane/feature branch is still safe and is what
# eliminates the 31% forgot-to-push sessions — only main is excluded.
if [[ "$branch" == "main" ]]; then
  echo "" >&2
  echo "  auto-push: SKIPPED — refusing to auto-push directly to main." >&2
  echo "  main only advances through a reviewed merge. If this commit was" >&2
  echo "  already independently reviewed, push it yourself:" >&2
  echo "    git push -- $remote main:main" >&2
  echo "" >&2
  exit 0
fi

# Push using a fully-qualified refspec, not a bare branch name. A bare
# name like "$branch" is ambiguous: git strips a LEADING '+' off the
# whole refspec token as a force-push flag before resolving the ref, and
# "+main" is a legal branch name — so an unqualified push of a branch
# literally called "+main" force-pushes local main over remote main.
# refs/heads/<branch>:refs/heads/<branch> has no leading '+' (the '+'
# lands inside the path, not at position 0), so it can never be
# reinterpreted as a force refspec. "--" stops git from reading a
# remote or branch name that begins with '-' as a flag.
refspec="refs/heads/$branch:refs/heads/$branch"
echo "" >&2
echo "  auto-push: committed — pushing $branch to $remote..." >&2
# "cmd | tail" makes a subsequent "if ...; then" check tail's exit
# status (always 0), not git push's, so a genuinely failed push
# (rejected, auth failure, network error) would be misreported as
# "pushed." PIPESTATUS[0] is the first command's (git push's) real exit
# code, captured without buffering the whole output in a variable. The
# pipeline itself is used as the "if" condition (with PIPESTATUS read
# in BOTH branches) rather than as a bare statement: a bare failing
# pipeline would trip "errexit" if this script ever inherits
# SHELLOPTS=errexit:pipefail from its caller's environment, killing the
# script before it ever reports the failure — a pipeline used as an
# if/while/until condition is exempt from errexit by definition.
if git push -- "$remote" "$refspec" 2>&1 | tail -5 >&2; then
  push_status=${PIPESTATUS[0]}
else
  push_status=${PIPESTATUS[0]}
fi
if [[ "$push_status" -eq 0 ]]; then
  echo "  auto-push: pushed." >&2
else
  echo "  auto-push: push failed — run: git push -- $remote $refspec" >&2
fi
echo "" >&2

exit 0
