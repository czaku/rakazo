
## 2026-09-10 — Bot turns on a Claude subscription run in visible herdr panes (Luke)

- **Decision:** when a rakazo bot uses a Claude subscription through a sweech profile (e.g. claude-pole), every bot turn runs inside a visible herdr pane — never as a hidden `claude` subprocess of the rakazo worker.
- **Options put to Luke:** (a) subprocess owned by the worker, shown in the thread and `sweech sessions` — recommended by the Fable design as "the bot's own mouth"; (b) every turn in a herdr pane — **chosen**; (c) no subscriptions in rakazo, key providers via sweech gateway only.
- **Why this matters / what it rules out:** the estate's never-headless rule is applied to the bot's own voice too, not only to delegated minions. It rules out `NativeCliRuntime` spawning `claude` from the launchd worker and the sweech daemon `POST /run` path for bot turns.
- **Consequences to design for:** one long-lived claude session per bot in the herdr `agents-kc` session (the keychain-capable server — the plain `agents` server gets exit 36), rakazo sends turns in and reads results back (transcript, not pane scraping), approvals and tools still go through rakazo. Revised design pending: review/sweech-integration-design.md.
- **Legal basis kept:** the unmodified `claude` binary signed in with Luke's own subscription is the permitted shape (code.claude.com legal-and-compliance, fetched 2026-09-10); rakazo's own Claude sign-in (pi-ai "Stealth mode") stays forbidden and is to be deleted.
