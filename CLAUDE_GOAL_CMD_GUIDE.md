# Native goal guide — rakazo

This guide applies to Claude Code and Codex CLI. A native /goal keeps one live CLI session pursuing a bounded objective; it does not replace this repository's backlog, SDLC, tests, proof, or human authority.

## Supported execution contract

- Use only live, materialized Claude Code or Codex CLI sessions.
- Never use claude -p, codex exec, or a Task/subagent goal lane.
- Legoalas v1 launches one dedicated orchestrator and one dedicated worker per active task in local tmux.
- Every target is driven from another PTY: a bootstrap controller launches and sets the orchestrator, while the goal-driven orchestrator launches and drives workers but never its own pane.
- Claude → Claude, Claude → Codex, Codex → Claude, and Codex → Codex are valid only after one exact per-profile executable wrapper passes runecode legoalas goal matrix. Its command JSON array contains that single absolute path and no positional arguments; for Sweech, resolve or create the dedicated profile wrapper and never call sweech use, sweech launch, or the generic sweech launcher.
- All four pairings support launch, goal setting, and lifecycle commands from a proven idle composer. Codex may interrupt an active turn only with a receipt-bound Interrupt Turn keymap probe; Claude Code 2.1.210 exposes no certifiable active-turn interrupt, so active Claude pause/stop fails closed and asks the human to attach and interrupt before the controller resumes from proven idle.
- Herdr, Cmux, and remote transports are unsupported until equivalent adapters pass the same matrix and receipt protocol.

## Two kinds of truth

Native status is liveness, not proof. A provider reporting active, achieved, or complete says what happened inside that session; it cannot mark a backlog task done.

A provider transition is accepted only from evidence bound to the certified pane identity, launch argv, pairing certificate, revision, and injection receipt. Product completion separately requires fresh tests, applicable visual evidence, independent review, and a signed SDLC proof receipt matching the worker commit.

Do not paste slash commands manually, trust copied terminal lines, or use raw pane captures as evidence. If the controller records a pending or ambiguous transition, automatic resend is forbidden; inspect its receipts and ask the human.

## Objective rules

Every objective must be one non-empty line of at most 4,000 provider-compatible JavaScript UTF-16 code units and contain:

1. **OBJECTIVE** — one finite outcome.
2. **PROCESS** — follow SDLC.md and the repository's branching/versioning rules.
3. **SCOPE** — exact backlog task IDs or orchestrator run.
4. **DONE WHEN** — acceptance criteria mapped to fresh evidence and signed proof at HEAD.
5. **HARD CAP** — task, turn, and wall-clock limits.
6. **GATE** — independent adversarial review (codex by default), plus visual verification for user-visible work.
7. **HUMAN** — ask on unclear intent, unavailable capability, ambiguous state, approval boundaries, or conflicting evidence.

PROCESS: SHAPE → SPEC → BACKLOG → AUDIT → BUILD → GATE → VISUAL → PROOF; STOP at PROOF. The operator closes the task during MERGE.

Validate the file; do not approximate the provider limit with shell character counting:

~~~bash
runecode legoalas goal validate --objective-file "$OBJECTIVE_FILE"
~~~

## Orchestrator objective shape

~~~text
OBJECTIVE: deliver the approved finite backlog; PROCESS: follow SDLC.md and repository branching/versioning policy; SCOPE: <task IDs and dependency order>; DONE WHEN: every task has a committed worker branch, independent PASS, current tests and visual evidence where applicable, signed proof matching HEAD, successful integration, and the configured backlog source updated; HARD CAP: <limits>; GATE: never merge over FAIL or provider status alone; HUMAN: pause and ask one concrete question whenever intent, capability, side effect, or evidence is unclear.
~~~

The orchestrator assigns dependency-ready tasks, validates worker proof, integrates commits, reruns integration gates, and updates the backlog source. It does not accept provider goal completion as proof and does not deploy.

## Worker objective shape

~~~text
OBJECTIVE: deliver exactly <task ID> in <worktree>; PROCESS: follow SDLC.md through build, test, visual verification when applicable, independent review, and proof; DONE WHEN: every acceptance criterion maps to fresh evidence, required tests pass with counts, review is PASS, proof is signed against the committed branch HEAD, and the commit is ready for integration; HARD CAP: <limits>; NEVER: merge, mark backlog done, deploy, or approve your own work; HUMAN: stop and ask on ambiguity, unavailable capability, or unsafe side effect.
~~~

The worker is the product engineer and commits its branch. The orchestrator owns integration and backlog reconciliation after independent proof.

## Launch and lifecycle

Start through the strict public skill verb:

~~~text
/legoalas start <finite delivery goal>
~~~

Legoalas audits backlog quality, confirms the plan with the human, probes the exact orchestrator/worker pairing, generates launch argv, and uses the receipt-producing controller. Capability probes are safe metadata checks and may precede approval; human approval gates launch-tmux, which starts provider sessions. Before launch, create a unique state at .git/legoalas/runs/<run-id>/goal-state.json with runecode legoalas goal run init; never reuse a closed run or a legacy global state file. The bootstrap controller arms the orchestrator; its native goal provides persistence while it launches, monitors, and refills worker lanes through the same public CLI. A planned pause/stop lets the orchestrator drain workers before another PTY pauses/clears it; an emergency controller quiesces the orchestrator first, then workers, so it cannot refill during the drain. /legoalas start <same goal> may resume only when every required immutable lane still matches its live pane. A dead or replaced pane fails and fences that run; preserve it incomplete, ask the human, and only the human may initialize a new run id after reconciling backlog/worktree state. A verified final stop closes the run explicitly with runecode legoalas goal run close.

A pairing certificate may be used to launch/set only while fresh. Before each later worker launch, rerun the matrix into a new per-lane certificate and generate that lane's argv from it; retain the original certificate, argv, pane, and launch receipt with every live lane for later status, pause, resume, and clear.

If SDLC proof fails after provider completion, clear that worker with its original bound files, then set a revised objective only after a fresh no-goal preflight in the exact same live pane and executable. The re-arm keeps the original launch-bound pairing, argv, and receipt even after certificate freshness expires; a different pairing or session fails closed. Never overwrite or blindly resend the old transition.

If the backlog-quality skill or source is unavailable, selected work lacks acceptance criteria, a provider cannot be proven, or live state disagrees with receipts, stop safely and ask the human. Never weaken a gate merely to keep the loop moving.

## CoDo boundary

CoDo does not depend on native goals or Legoalas. Legoalas is an optional Claude/Codex execution adapter that CoDo may select; CoDo can schedule other providers through other adapters while retaining the same backlog, SDLC, proof, and human-fallback contract.
