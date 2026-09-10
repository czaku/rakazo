# SDLC — rakazo

> The one canonical pipeline. **Every engineering task goes through these stages, in order.** When `legoalas` drives `/goal` in this repo, **follow this file** — it is the process, not a suggestion. `done` means the code is **merged and the task is closed by the operator during MERGE against a signed proof that matches the merged HEAD** — never a claim in the transcript.

## The universal phases (all activities)

**SHAPE → SPEC → BACKLOG → AUDIT → BUILD → GATE → VISUAL → PROOF → MERGE → VERSION → RELEASE** Fixed doctrine. Each *activity* (engineering / research / content) binds its own skills to these stages — the stage names never change, the skills swap only at GATE.

## Engineering pipeline — 9 stages

| # | Stage | Skill | The gate |
|---|-------|-------|----------|
| 0 | SHAPE | `shape-the-product` | Fuzzy idea → clear direction: problem, scope, success criteria, non-goals, open decisions. Reality-checked against the running product. Its input may be a `the-full-teardown` audit. |
| 1 | SPEC | `spec-it-out` | Structured spec: requirements, design, data model, open questions, decisions. **SKIPPABLE** below a size threshold — record `SPEC: n/a + one-line justification` (same pattern as the visual gate). |
| 2 | BACKLOG | `backlog-plan-of-attack` | Spec → atomic tasks, each with acceptance criteria + ≥1 proof requirement. |
| 3 | AUDIT | `audit-backlog-blitz` | Fail-closed AC-coverage gate — refuses any task with empty / weak / prose-only criteria, or an AC that hard-requires an unavailable secret instead of degrading gracefully. |
| 4 | BUILD | `grind` | Build ONE task in its own worktree; wired/dead-code check; repeatable test; no self-advance, no self-merge, no push to the shared trunk — MAY push its own lane branch to origin as a backup. Session-level `handoff` at ~5 tasks or high context. Convergence ceiling: hard stop at N codex-FAIL rounds. |
| 5 | GATE | `review-no-mercy` + `fabrication-buster` (+ `straight-talk`) | Independent review by a different engine (codex by default) — never a self-review, never the builder's engine, never a claude subagent, never skippable. RUN-don't-READ: execute the acceptance command and record its real exit code. Ends VERDICT: PASS/FAIL, fail-closed. Activity swap: research → `verify-claims`; content → `copy-review`. |
| 6 | VISUAL | `pixel-perfection-audition` | If the task touched anything a human sees, screenshot light + dark and verdict it; otherwise declare `no visual surface — skipped intentionally`. |
| 7 | PROOF | `proof-of-the-pudding` | Aggregator, fail-closed. Every upstream gate present + fresh (== HEAD) + PASS; sign ONE receipt under `proof/<TASK-ID>/` **and attach it to the task** (proofReference). Any gate absent/stale/FAIL → not ready for MERGE. |
| 8 | MERGE | `merge-the-perfect-code` | The ORCHESTRATING AGENT only ("operator" is the parent agent, NOT the human) — NO build unit self-merges. The operator merges AND pushes; a clean, gated, rebased lane is never parked behind a human confirmation. Rebase → re-verify the attached proof survives the rebase (pin to the TREE HASH; re-run the test always, codex only on conflicts/overlap) → `merge --no-ff` → clean up: remove worktree + kill the herdr/tmux lane session + delete the lane branch (local AND its remote backup, if pushed) + `keel task done` + closing note. The operator pushes the merged base — committed but not pushed is not done, and an unpushed base is invisible to the other machine and to every later lane that rebases onto it. After the LAST lane of a wave: a wave-close **SYNTHESIS** (full suite + e2e smoke on the merged base). MERGE closes the record — there is no separate DONE stage. |
| 9 | VERSION | `release` | Uniform and mechanical for every artifact: semver bump per the repo's own rules, roll the CHANGELOG `Unreleased` section into the version, tag. The receipt is that EVERY manifest in the repo agrees on the new version — a half-applied bump is worse than none, because the running artifact and the declared version then disagree. Separate from RELEASE on purpose: bumping and shipping fail INDEPENDENTLY, and folding them into one stage is what let five consecutive bumps ship nothing (the installed CLI sat at 0.9.1 against a 0.9.6 repo, serving a stale skill bundle for weeks). |
| 10 | RELEASE | `release` | Dispatched on TYPE x TARGET, both declared per project in `runecode.yaml` under `release:` — never guessed, and never hardcoded in this stage. Each target declares `run` / `verify` / `expect`, and `expect` interpolates the manifest version, so the operator MUST NOT declare a release without personally asserting that the RUNNING artifact reports the new version — enforced by this stage's discipline, not (yet) by an executable runner; see T-LU-379. FAIL-CLOSED: a target whose `verify` reports the old version is NOT released, and an UNREACHABLE target makes the stage INCOMPLETE and names the host — "released" must never quietly mean one machine out of two. Every target is receipted individually. A project with no `release:` section is told so rather than guessed at. The stage owns the RECEIPT, not the command: hardcoding product tooling here would rot exactly the way drifted hardcoded commands did across this estate's skills. |

**Order is load-bearing:** SHAPE → SPEC → BACKLOG → AUDIT → BUILD → GATE → VISUAL → PROOF → MERGE → VERSION → RELEASE. Workers execute through PROOF and stop with an attached signed receipt. Only the operator executes MERGE; MERGE re-verifies the receipt, integrates the code, cleans up the lane, and closes the task. There is no separate DONE stage.

## Non-engineering activities (the taxonomy holds, the gate swaps)

- **research** — build with `deep-research`; the GATE is `verify-claims` (every claim → a source you opened or a command you ran), **not** codex. Forcing a code reviewer on prose yields a vacuous PASS.
- **content** — the GATE is `copy-review` (no fabricated quote/stat + craft), **not** codex.

## Branching

- One mainline: `main`. No long-lived feature branches.
- Each task builds in its **own git worktree** at `.worktrees/<slug>-<task>/` on branch `lane/<task>`. It commits locally, and SHOULD push that lane branch to origin as a backup; it **never pushes to the shared trunk, never merges, never closes the task** — the operator harvests at MERGE.
- keel is the single source of truth for tasks (prefix `T-`). `proof/<TASK-ID>/` holds the signed receipts.

## Delivery mode — tmux worker-lanes (multi-model)

Each task runs as its **own tmux session in its own git worktree**, driven by `/goal` (or `grind`). Lanes can run **any engine** (Claude / codex / GLM / Kimi via sweech) — this is how you parallelise across models.
- One worktree per task at `.worktrees/<slug>-<task>/` on branch `lane/<task>`.
- A lane builds → gates → **stops**. It **never self-merges** and never pushes to the shared trunk — it SHOULD push its own lane branch to origin as a backup.
- The operator (a session above the lanes) harvests: rebase → re-verify the proof on the moved head → `merge --no-ff` → close the task → remove the worktree.
- Liveness is a **real pane capture** (`capture-pane -S -40`; `tail -N` is banned — the spinner sits ~6 lines above the input box) + a `git fetch` before reading a repo a worker pushes to.
- **Stop is the human's button.** The loop is session-bound — it dies with the session; no out-of-session resurrector.

## Standing discipline — `straight-talk` (every stage, always on)

The most dangerous failure in this pipeline is the **yes-man**: a gate that rubber-stamps, a reviewer that softens a real flaw, an agent that calls something done over an open failure or caves when the human pushes back. RLHF makes agreement the default drift — **`straight-talk` overrides it at every stage**:

- **Truth over agreement.** Lead with the problem; strongest objection first, with evidence.
- **Hold the line.** Change a verdict only on new evidence or better logic — never because a human pushed back, got annoyed, or outranks you.
- **A FAIL is not-ready.** A red gate / failed review / FAIL verdict is never shippable — no "small / archived / already merged / not the main path" exemption.
- **No tells.** No "you're absolutely right", no praise-openers, no compliment-sandwiches, no softening a real flaw.

## The one hard law

**A state-word is an exit code, never a belief.** `proof-ready` = a signed `proof-signoff` receipt matching HEAD; `done` = the operator completed MERGE and closed the task against that receipt. UNREACHABLE ≡ UNCONFIRMED ≡ FAIL. The GATE engine is always a **different engine than the builder**, and it is never a **yes-man** (`straight-talk`). A **FAIL is not-ready** — never shipped over, never exempted. No gate → not ready for MERGE.
