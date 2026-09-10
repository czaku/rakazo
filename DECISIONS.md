
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
