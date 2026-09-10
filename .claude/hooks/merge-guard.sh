#!/usr/bin/env bash
# Rune: merge-guard — PreToolUse Bash hook.
# Blocks git merge if no review evidence exists for the branch being merged.
# Review evidence: .reviews/{branch}.json with "passed": true
# Exit code 2 = block + message.

input=$(cat)

# Cheap pre-filter ONLY. It must never be narrower than the real check below:
# the previous pattern required the word git and the word merge to be ADJACENT,
# so `git -C DIR merge X` — an ordinary form — never triggered the guard at all
# and sailed straight past it. Matching the bare word instead over-selects, and
# the tokenizer below is what actually decides. That also stops the guard firing
# on prose that merely mentions merging inside an unrelated command.
echo "$input" | grep -qE '"command".*git' || exit 0

# ONE tokenizer decides everything: whether this really is a merge invocation,
# which branch it names, and which directory governs it. Deriving the branch by
# splitting the raw string (the old approach) mis-parsed quoted commands and
# produced branch names with a trailing quote.
parsed=$(echo "$input" | python3 -c "
import sys,json,shlex,re
d = json.load(sys.stdin)
cmd = d.get('tool_input', d.get('input', {})).get('command', '')
# Split on every sequencing operator, not just &&. Missing || and the pipe let
# 'git -C /missing status || git merge unreviewed' parse as the status call only.
segments = [s for s in re.split(r'\|\||&&|;|\n|\||&', cmd) if s.strip()]

def toks(s):
    try:
        return shlex.split(s)
    except ValueError:
        return s.split()

# Git-level flags that consume the NEXT token as their value.
GIT_VALUED = ('-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path')
# merge flags that consume the next token. Missing these was a false-ACCEPT:
# 'merge -m reviewed-msg unreviewed-branch' read the MESSAGE as the branch, so a
# passing review for a branch named like the message cleared an unreviewed merge.
# -S/--gpg-sign take an OPTIONAL attached argument only, so they must NOT consume
# the next token — treating them as valued made 'merge -S unreviewed' skip the
# real operand entirely and exit 0.
MERGE_VALUED = ('-m', '-F', '-s', '-X', '--strategy', '--strategy-option',
                '--into-name', '--message', '--file', '--cleanup', '--log')

def strip_env_prefix(t):
    # 'env FOO=bar git merge X' and a bare 'FOO=bar git merge X' both prefix the
    # real command with assignments. Drop them so the git invocation is visible.
    k = 0
    if k < len(t) and t[k].rsplit('/', 1)[-1] == 'env':
        k += 1
    while k < len(t) and '=' in t[k] and not t[k].startswith('-'):
        k += 1
    return t[k:]

def git_index(t):
    # git may be invoked by path: /usr/bin/git, ./git, or via env. Matching the
    # bare token only was a bypass — a path-qualified invocation merged while
    # the guard saw nothing.
    for i, p in enumerate(t):
        if p == 'git' or p.rsplit('/', 1)[-1] == 'git':
            return i
    return None

def subcommand(t):
    # The git subcommand and its argv, or (None, None) if this is not git.
    gi = git_index(t)
    if gi is None:
        return None, None
    k = gi + 1
    while k < len(t):
        p = t[k]
        if p in GIT_VALUED:
            k += 2
        elif p.startswith('-'):
            k += 1
        else:
            # First non-flag token IS the subcommand. Checking position rather
            # than membership stops 'git -C merge status' reading as a merge and
            # stops 'git log --grep merge' doing the same.
            return p, t[k+1:]
        continue
    return None, None

def first_operand(argv):
    k = 0
    while k < len(argv):
        p = argv[k]
        if p in MERGE_VALUED:
            k += 2
        elif p.startswith('-'):
            k += 1
        else:
            return p
    return ''

# A wrapper hides the command from this tokenizer entirely: sh -c, eval, command
# substitution, or a backtick can run a merge that no amount of parsing here will
# see. Static analysis of arbitrary shell cannot decide this, so the guard stops
# pretending it can and DECLINES the command instead of waving it through. Only
# commands that mention git are affected, and the remedy is to run the merge as a
# plain command.
# 'env' is deliberately NOT here: 'env FOO=bar git merge X' is perfectly
# analysable once the VAR=val prefix is skipped, and refusing it was a
# false-block on an ordinary command.
OPAQUE = ('sh', 'bash', 'zsh', 'eval', 'xargs')
def opaque(cmd_text, all_tokens):
    if (chr(36) + chr(40)) in cmd_text or chr(96) in cmd_text:
        return True
    for t in all_tokens:
        if t and t.rsplit('/', 1)[-1] in OPAQUE:
            return True
    return False

all_toks = [x for s in segments for x in toks(s)]
# Look for git in the RAW TEXT, not the tokens: a shell wrapper hides git inside
# a quoted argument, so there is no bare git token to find — which is precisely
# why the wrapper is opaque in the first place.
# WORD boundary, not substring. Testing 'git' in cmd matched any URL or path
# containing those three letters — a raw.githubusercontent.com fetch alongside
# any substitution was refused as a wrapped git call. That false-blocked four
# ordinary commands in a single session. A wrapper still hides a real quoted
# invocation, and that still matches on the boundary.
if re.search(r'\bgit\b', cmd) and opaque(cmd, all_toks):
    print('')
    print('OPAQUE')
    print('')
    sys.exit(0)

# An alias defined ON THE COMMAND LINE is invisible to the resolver downstream,
# which asks the REPOSITORY's config. 'git -c alias.m=merge m BRANCH' is a real
# merge that answered nothing to 'git config --get alias.m' and so exited clean.
# Deciding what such a command expands to means re-implementing git's own alias
# machinery, which is the same losing game as parsing shell — so it is DECLINED.
# Both spellings count: '-c k=v' and '-c' 'k=v', plus --config-env which names
# an environment variable holding the value.
def defines_alias_inline(all_tokens):
    for i, t in enumerate(all_tokens):
        if not t:
            continue
        if t.startswith('--config-env=') and t[len('--config-env='):].startswith('alias.'):
            return True
        if t == '--config-env' and i + 1 < len(all_tokens) and all_tokens[i + 1].startswith('alias.'):
            return True
        if t.startswith('-c') and len(t) > 2 and t[2:].lstrip('=').startswith('alias.'):
            return True
        if t == '-c' and i + 1 < len(all_tokens) and all_tokens[i + 1].startswith('alias.'):
            return True
    return False

if re.search(r'\bgit\b', cmd) and defines_alias_inline(all_toks):
    print('')
    print('INLINE_ALIAS')
    print('')
    sys.exit(0)

# Consider EVERY git segment, not just the first. Taking the first one let
# 'git -C /missing status || git merge unreviewed' resolve to the status call
# and exit before the real operation was ever examined.
candidates = []
for s in segments:
    c, a = subcommand(strip_env_prefix(toks(s)))
    if c is not None:
        candidates.append((c, a, s))
if not candidates:
    sys.exit(0)
sub, argv, seg = next((x for x in candidates if x[0] == 'merge'), candidates[0])

branch = first_operand(argv)
if not branch:
    sys.exit(0)

# REFUSE AMBIGUITY RATHER THAN RESOLVE IT. Collect every directory the whole
# command names. If it names more than one, this guard cannot know which one
# git ends up in without simulating a shell, so it declines instead of guessing.
# That defeats 'cd ATTACKER && git -C TARGET merge X' with no parser cleverness
# to outwit: two directories, therefore refused.
# Every form that can relocate git: -C, and --git-dir / --work-tree in BOTH the
# space and the equals spelling. Missing the equals spelling was a false-ACCEPT:
# the guard read evidence in the working directory while git operated elsewhere.
def dirs_named(st):
    out = []
    for j, p in enumerate(st):
        if p in ('-C', '--git-dir', '--work-tree') and j + 1 < len(st):
            out.append(st[j+1])
        elif p.startswith('--git-dir=') or p.startswith('--work-tree='):
            out.append(p.split('=', 1)[1])
    if st and st[0] == 'cd' and len(st) > 1:
        out.append(st[1])
    return out

named = []
for s in segments:
    named.extend(dirs_named(toks(s)))

# A .git suffix and its worktree denote the same repository; normalise so a
# single --git-dir does not read as two distinct directories.
norm = set(re.sub(r'/\.git/?$', '', d) for d in named)

print(branch)
print('AMBIGUOUS' if len(norm) > 1 else (named[0] if named else ''))
print(sub)
")
parse_rc=$?

# The analyzer failing is NOT the same as finding no merge, and conflating the
# two makes this gate fail OPEN — which it did: a stray quote in a comment broke
# the embedded python, stderr was discarded, the output came back empty, and the
# guard exited 0 on every command while appearing healthy. A guard that cannot
# analyse a command must REFUSE it, never wave it through.
if [[ $parse_rc -ne 0 ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — the guard could not analyse this command" >&2
  echo "  (analyzer exit $parse_rc). An undetermined command is a REJECTION." >&2
  echo "" >&2
  exit 2
fi

branch=$(printf '%s' "$parsed" | sed -n '1p')
target_dir=$(printf '%s' "$parsed" | sed -n '2p')
subcmd=$(printf '%s' "$parsed" | sed -n '3p')

# OPAQUE is decided FIRST: it deliberately carries no branch, so an
# empty-branch early exit placed above it would wave every wrapped command
# through — the refusal has to outrank the shortcut.
if [[ "$target_dir" == "OPAQUE" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — this command wraps git in a shell, eval, or a" >&2
  echo "  substitution, so what it actually runs cannot be determined by reading" >&2
  echo "  it. An undetermined command is a REJECTION. Run the merge directly." >&2
  echo "" >&2
  exit 2
fi

# Same class, different vector: the alias is defined ON THE COMMAND LINE, so the
# resolver below — which asks the REPOSITORY's config — cannot see it, and
# 'git -c alias.m=merge m BRANCH' merged unrecognised.
if [[ "$target_dir" == "INLINE_ALIAS" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — this command defines a git alias inline (-c" >&2
  echo "  alias.* or --config-env=alias.*), so the subcommand it really runs" >&2
  echo "  cannot be resolved from the repository's config. An undetermined" >&2
  echo "  command is a REJECTION. Run the merge directly." >&2
  echo "" >&2
  exit 2
fi

# Genuinely not a merge — the analyzer ran fine and found no operand.
[[ -z "$branch" ]] && exit 0

# Ambiguity is decided BEFORE alias resolution: resolving an alias against one of
# several candidate directories would pick a repo arbitrarily, and 'git -C A -C B
# m branch' would then slip past on whichever answered first.
if [[ "$target_dir" == "AMBIGUOUS" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — this command names more than one directory, so" >&2
  echo "  which repository the merge lands in cannot be determined without" >&2
  echo "  simulating a shell. Run the merge as its own command." >&2
  echo "" >&2
  exit 2
fi

# A user alias makes the subcommand unreadable from the text alone: with
# 'alias.m = merge', 'git m branch' IS a merge and used to sail past entirely.
# Resolve the alias through git itself rather than guessing. An alias that cannot
# be read is NOT assumed innocent when the repo is unknown.
if [[ "$subcmd" != "merge" ]]; then
  alias_dir="$target_dir"
  [[ -z "$alias_dir" ]] && alias_dir="."
  expansion=$(git -C "$alias_dir" config --get "alias.${subcmd}" 2>/dev/null)
  # A '!' expansion is a SHELL command, not a git subcommand. It can carry its
  # own operands — 'alias.m = !git merge release' — so the branch this guard
  # extracted from the visible text is not the branch that gets merged, and the
  # review evidence would bind to the wrong one. Whether it merges at all is
  # undecidable from here for exactly the reason the OPAQUE refusal exists.
  case "$expansion" in
    '!'*)
      echo "" >&2
      echo "  merge-guard: BLOCKED — alias '$subcmd' expands to a shell command" >&2
      echo "  ('!' form), which can carry its own operands. The branch named here" >&2
      echo "  is not necessarily the branch merged, so review evidence cannot be" >&2
      echo "  bound to it. An undetermined command is a REJECTION." >&2
      echo "" >&2
      exit 2
      ;;
  esac
  case " $expansion " in
    *" merge "*|*" merge"|"merge "*) ;;
    *) exit 0 ;;
  esac
fi

[[ -z "$target_dir" ]] && target_dir="."
# A --git-dir names the .git directory itself, which is not a valid -C target;
# resolve to its worktree so the lookup succeeds for the right reason rather
# than failing and blocking by accident.
target_dir="${target_dir%/.git}"
target_dir="${target_dir%/.git/}"

repo_root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$repo_root" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — cannot determine which repository this merge targets." >&2
  echo "  An undetermined repo is a REJECTION: the review file this would otherwise" >&2
  echo "  trust could belong to a different repo with a same-named branch." >&2
  echo "" >&2
  exit 2
fi

# Check for review evidence, in the repo being merged
review_file="${repo_root}/.reviews/${branch}.json"
if [[ ! -f "$review_file" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — no review evidence for branch '$branch'" >&2
  echo "" >&2
  echo "  Before merging, run a review and write results to:" >&2
  echo "    $review_file" >&2
  echo "" >&2
  echo "  The review file must contain: {"passed": true, ...}" >&2
  echo "  Run /code-review on the branch diff first." >&2
  echo "" >&2
  exit 2
fi

# A review file is only evidence if it can be TIED to the branch being merged.
# Task ids are reused across sibling repos, so a same-named branch elsewhere
# would otherwise let one repo's review clear another repo's merge.
if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/${branch}"; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — branch '$branch' does not exist in $repo_root," >&2
  echo "  so the review file found there cannot be tied to what you are merging." >&2
  echo "" >&2
  exit 2
fi

# Check if review passed
passed=$(python3 -c "import json; d=json.load(open('$review_file')); print(d.get('passed', False))" 2>/dev/null)
if [[ "$passed" != "True" ]]; then
  echo "" >&2
  echo "  merge-guard: BLOCKED — review for '$branch' did not pass." >&2
  echo "  Fix the issues in $review_file and re-review." >&2
  echo "" >&2
  exit 2
fi

exit 0
