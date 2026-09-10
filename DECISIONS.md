
## 2026-09-10 — Bot turns on a Claude subscription run in visible herdr panes (Luke)

- **Decision:** when a rakazo bot uses a Claude subscription through a sweech profile (e.g. claude-pole), every bot turn runs inside a visible herdr pane — never as a hidden `claude` subprocess of the rakazo worker.
- **Options put to Luke:** (a) subprocess owned by the worker, shown in the thread and `sweech sessions` — recommended by the Fable design as "the bot's own mouth"; (b) every turn in a herdr pane — **chosen**; (c) no subscriptions in rakazo, key providers via sweech gateway only.
- **Why this matters / what it rules out:** the estate's never-headless rule is applied to the bot's own voice too, not only to delegated minions. It rules out `NativeCliRuntime` spawning `claude` from the launchd worker and the sweech daemon `POST /run` path for bot turns.
- **Consequences to design for:** one long-lived claude session per bot in the herdr `agents-kc` session (the keychain-capable server — the plain `agents` server gets exit 36), rakazo sends turns in and reads results back (transcript, not pane scraping), approvals and tools still go through rakazo. Revised design pending: review/sweech-integration-design.md.
- **Legal basis kept:** the unmodified `claude` binary signed in with Luke's own subscription is the permitted shape (code.claude.com legal-and-compliance, fetched 2026-09-10); rakazo's own Claude sign-in (pi-ai "Stealth mode") stays forbidden and is to be deleted.

## 2026-09-10 — Sweech profiles are discovered live and chosen per bot, never hardcoded (Luke)

- **Decision:** rakazo discovers the sweech profiles that exist on the machine it runs on, live, and lets Luke select or change a bot's profile, model and fallback order from the UI at any time. No profile names, accounts or fallback orders are baked into code, config defaults or memory.
- **Options put to Luke:** (a) claude-pole only for week one — recommended; (b) claude-pole → claude-minimax; (c) claude-pole → claude-rai. **Rejected all three as fixed choices:** "This should be fully configurable. It should dynamically be able to explore sweech profiles on the machine it's running and I should be able to select, change."
- **Consequences:** the profile list comes from sweech at request time (e.g. `sweech list --json` / daemon `/models` + launch-identity), shows health/quota, and is re-validated when a turn starts; a bot whose profile disappears fails loudly with a pick-another prompt; fallback order is per-bot data edited in the bot panel. Matches the estate rule that the account is always Luke's call.

## 2026-09-10 — If the Studio dies while Luke travels: cold standby, promoted by hand (decided by Claude at Luke's delegation)

- **Luke:** "You decide… the MacBook is the machine I travel with… open, closed… the Mac Studio is meant to be the main one that's on all the time."
- **Decision:** the Studio stays the only brain. The MacBook is a travelling client and, when awake, a pair of hands. Standby = a nightly Postgres dump + DATA_DIR copy the MacBook pulls whenever it is online, plus a one-way promotion runbook used only in an emergency. No automatic failover.
- **Rejected:** hot standby (a replica on a laptop that is closed most of the day never stays current and costs ~2 days before the trip); "nothing" (a dead Studio would lose the last day of conversations and memory).
- **Reason:** single writer means nothing to merge when the Studio comes back; the real risk for the trip is the Studio not recovering on its own after a restart, which is handled first (boot/login/services audit, T-RKZ-012 already makes services self-restart).

## 2026-09-10 — Bot roster: one orchestrator + one bot per area (Luke)

- **Decision:** Luke talks mainly to one orchestrator, plus one bot per area, and can talk to any bot directly ("There will be bots on many levels, and I can talk to any of them, but ideally I would talk to one orchestrator plus one lead per area").
- **Areas with a bot (Luke, 2026-09-10):** Influencing · Fitkind · Goala · Quick revenue kits · System (estate tooling) · Thraive · Demix (Stashbar belongs to Demix — "demix and stashbar are the same"). More to be proposed from activity.
- **Rejected:** Fable's "two bots only, add a lead when traffic earns it" (review/fable-roster.md) and the Hermes-era 4-head roster (Influencing/Revenai/Products/Coding Harness) — the latter used agents' names, not Luke's.
- **Evidence behind it:** review/activity-by-area.md (14-day prompts+commits, both Macs) and review/gas-language.md (Luke's own vocabulary: orchestrator → areas/topics → specialised bots; Space = a function inside an area).
- **Guardrail kept from Hermes:** bots coordinate through keel rows, not bot-to-bot chat (the $300/day relay lesson).
