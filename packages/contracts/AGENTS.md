<session-context>
Routine software-engineering session on a repository the user owns and maintains.
The installed toolkit includes code-quality and release-readiness skills whose
vocabulary (vulnerability checklists, independent critical review) is used solely
to review this project's own code defensively before release. No activity here
analyzes or targets third-party systems, and no offensive tooling is built.
References to parallel worker sessions describe supervised builds of this
repository, each launched and merged with explicit human confirmation.
</session-context>

# @rakazo/contracts

## Tech Stack
TypeScript

## Key Commands
- `npm run dev` — start development
- `npm run test` — run tests

## Conventions
- [Add your naming conventions here]
- [Add file organization rules here]

## Architecture Notes
- [Add important architectural decisions]
- [Add things Claude Code must NOT break]

## The tannoy board — READ IT BEFORE EVERY TASK
- **Before picking up ANY task, read the board.** It carries the estate's live notices —
  dated, scoped and expiring — grouped MUST / SHOULD / COULD / WON'T:
```bash
  tannoy read --repo "$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")" \
              --machine "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" \
              --engine claude
```
- **Every notice that applies to this repo, machine and engine is binding — follow it as a
  bible.** A MUST is not advice, and not a default to weigh against your own judgement. The
  board exists because standing rules written in files were measurably ignored anyway; it is
  the delivery mechanism, so a notice reaching you IS the instruction.
- **A notice OVERRIDES your habit and anything stale in this file.** The board is dated and
  this file is not, so where they disagree the board wins. Scope and expiry are part of the
  rule: a notice scoped to another repo, or already expired, does not apply — and applying it
  anyway is its own error.
- **An unreachable board is NOT an empty board.** If the read errors, times out, or the
  service is not running, SAY SO and ask — never proceed as though there were no notices.
  Silence and "no notices" print identically and mean opposite things.
- Re-read it when you pick up the NEXT task, not once per session. Notices are posted while
  sessions are already running, and a session that started before a notice was posted is
  exactly the case the board was built for.

## Worker Delegation — Minion
- Delegate every worker through `/minion`; never use provider-native Agent/Task/multi-agent facilities, native subagents, or hidden headless workers.
- The parent agent alone launches, observes, steers, reconfigures, and stops Minions.
- Minions never launch Minions.

## Do Not
- [Add anti-patterns specific to this project]
- [List generated files that should never be edited manually]

## Library / Package Rules
- The public API surface is a contract — never change exported signatures without a major version bump
- Every public function must have tests before marking the task done
- Run `tsc --noEmit` before every commit — zero type errors allowed
- Document breaking changes in `CHANGELOG.md` before tagging a release
- Consumers come first: check all known consumers before changing a shared utility

## Surface Parity (if applicable)
If this tool has multiple surfaces (CLI / TUI / web dashboard / API):
- Any feature added to one surface MUST be added to all surfaces in the same PR
- Before marking a task done, verify each surface is updated
- "CLI only" is not done if a TUI or dashboard also exists

## Definition of Done (Tool)
- [ ] TypeScript compiles: `tsc --noEmit`
- [ ] Tests pass — show actual pass/fail counts
- [ ] Public API surface checked: no unintended breaking changes
- [ ] All surfaces updated (CLI + TUI + web if applicable)
- [ ] CHANGELOG.md updated if public API changed
- [ ] Committed AND pushed

## Screenshot Storage
Save every screenshot to `~/Desktop/screenshots/{project-name}/`.
Use the current git repo name as `{project-name}` and create the directory before capture:

```bash
export PROJECT_SCREENSHOT_DIR=~/Desktop/screenshots/$(basename "$(git rev-parse --show-toplevel)")
mkdir -p "$PROJECT_SCREENSHOT_DIR"
```

Do not keep proof, review, or catalog-upload screenshots in `/tmp`.

## Forbidden Language (cross-reference: forbidden-language hook)

The `forbidden-language` hook enforces the rules below.

In commit messages — these phrases are blocked:
- `pre-existing`, `out of scope`, `for now`, `will fix later`, `table this`,
  `TODO: fix`, `skipping for now`. Land the real fix or open a follow-up
  keel task; never paper over the regression in a commit message.

In proof artifacts (handoffs, keel notes, design docs) — these phrases
require a screenshot path nearby (.png/.jpg/screenshots/PROJECT_SCREENSHOT_DIR):
- `looks correct`, `should work`, `rendered successfully`, `visually verified`.
  Without a screenshot path, the hook blocks the write.

Banned destructive commands — always blocked:
- `git reset --hard`, `git push --force` / `-f`, `rm -rf .git`,
  `rm -rf node_modules` (without explicit `--force-confirm`).

Override: include `runecode: allow <reason>` in the input. Every override
appends a JSONL record to `~/.runecode/audit.log` (mode 0600; timestamp,
hook, cwd, reason truncated to 200 chars, engine, 500-char input snippet —
secrets like `sk-…` / `Bearer …` / `api_key=…` are redacted before write).
On audit-write failure (no python3, unwritable dir) the hook prints
`[audit] WARN:` to stderr and proceeds unrecorded (fail-loud).
View with `runecode overrides`.

## Codex Destructive-Command Ban (cross-reference: codex-destructive-guard hook)

When the active engine is `codex-*` (per `RUNECODE_ENGINE` env var or HEAD
commit `Engine:` trailer), these git commands are refused:
`git reset --hard`, `git push --force` / `-f`, `git checkout -- <path>`,
`git rebase -i`, `git filter-branch`.

Source: Apr 15 2026 lost 517 commits to a Codex-driven `reset --hard`.
Recovery took two days from the reflog. Claude is not affected by this hook.

Safer alternatives: `git revert <commit>` (reversible),
`git reset --soft HEAD~N` (keeps changes staged),
`git push --force-with-lease` (fails on conflict).

Override: include `runecode: allow-destructive --reason <text>` in the command.
Every override appends to `~/.runecode/audit.log`; view with
`runecode overrides --hook codex-destructive-guard`.

## Standing Git Rule

- Commit AND push valuable work without asking permission — committed but not
  pushed is not done.
- Never force-push. Always keep previous code browsable — no history-destroying
  ops (`git push --force`/`-f`, `git reset --hard` on shared history,
  `git filter-branch`, `rm -rf .git`). Every prior commit must stay reachable.
- Squash or force-push ONLY when the user explicitly asks for it — and even then
  prefer `git push --force-with-lease` over `--force`.

## Versioning & Releases (cross-reference: version-bump pre-push hook)

Every code change bumps the version — at least PATCH (semver 0.x). A frozen version
means "no code changed", so never ship code edits without bumping. Use
`onlytools release <tool> <patch|minor|major>` (bumps package.json/pyproject.toml,
rolls CHANGELOG.md Unreleased→version, then builds/tests/commits/tags/pushes) or the
`/release` skill. Bump type: fix/chore/docs/dep → patch, new feature/flag/endpoint
→ minor, stable-API break → major (lead approval).

The local `pre-push` hook (`onlytools install-hooks <tool>`) blocks a push when tracked
source changed without a bump; `onlytools check <tool>` runs it on demand. Override only
when justified: `SKIP_VERSION_CHECK=1 git push`, or add `[skip-version]` to the commit.
After bumping, rebuild + reinstall any installed artifact so the running version matches.

## Working File
- This repository uses `AGENTS.md` as the project instruction file.