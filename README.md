# grill-me-kimi

Two AI models harden your plan before you write a line of code.

There are two gaps in AI-assisted coding:

1. The gap between **you and Claude** — do you agree on what to build?
2. The gap between **Claude and the quality of what it produces** — is the plan
   actually correct, and how would you, a non-expert, know?

Skills like `grill-me` close gap 1: Claude interrogates you until the plan is locked.
But the same model that wrote the plan is a poor judge of it — ask Claude to grade
its own work and it says A+. That's an echo chamber.

This family closes gap 2 by bringing in a **second model from a different provider**.
**Act 1** grills you to lock the plan. **Act 2** hands that plan to **Kimi**, which
adversarially tears it apart over several rounds until both models sign off. Only
then do you build.

You gate twice — at kickoff and at final sign-off. Kimi is read-only the whole time.
Two artifacts come out: `PLAN.md` (the clean final plan — the *what*) and
`PLAN-REVIEW-LOG.md` (the round-by-round debate — the *why*).

## The skills

| Skill | Act 1 | Act 2 |
|---|---|---|
| `grill-me-kimi` | Claude interrogates you one question at a time until the decision tree is resolved | Kimi adversarial review loop |
| `grill-with-docs-kimi` | Same, but challenges your plan against your project's `CONTEXT.md` glossary + writes ADRs inline | Kimi review loop |
| `kimi-review` | — (you already have a plan) | Kimi review loop |

## How Act 2 works

1. Claude writes the locked plan to `PLAN.md` and starts a log at `PLAN-REVIEW-LOG.md`.
2. **Round 1:** Kimi reviews the plan in a read-only sandbox (`--plan` mode) and
   returns numbered concerns ending in `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.
3. **Rounds 2..N:** Claude revises the plan (or rebuts in the log); the **same Kimi
   session is resumed** (`--continue`) so it remembers its concerns and checks whether
   they're addressed.
4. Bounded by `MAX_ROUNDS` (default 5). Terminates on `APPROVED` or the cap.
5. You gate twice only: kickoff, and final sign-off before any code. Kimi only ever
   reads the plan and the codebase.

## Why Kimi (and not the OpenAI Codex original)?

This is a port of the `grill-me-codex` idea to [Kimi](https://www.kimi.com). The
review runs through the **Kimi Code CLI**, which logs in with your **Kimi account via
OAuth** — no API key, no per-token billing. The engine just shells out to `kimi`, so
auth is the CLI's concern: log in once and every review runs on your subscription.

Swapping in a different model is a one-line change in `bin/kimi-review.sh` (the `kimi`
invocation) — point it at any CLI or local model you like.

## Install

### Prerequisites

```bash
brew install kimi-cli   # macOS; see https://github.com/MoonshotAI/kimi-cli for others
kimi login              # OAuth — opens a URL, sign in with your Kimi account
```

### The skills

```bash
./install.sh            # copies skills/* into ~/.claude/skills/ and chmods the engine
```

Or manually:

```bash
cp -r skills/* ~/.claude/skills/
chmod +x ~/.claude/skills/*/kimi-review.sh
```

Then in Claude Code: `/grill-me-kimi`, `/grill-with-docs-kimi`, or `/kimi-review`.

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `KIMI_MODEL` | your OAuth plan's default | Pin a model, e.g. `kimi-k2.6` |
| `KIMI_NO_THINKING` | unset (thinking on) | Set to `1` to disable Kimi's thinking mode |
| `KIMI_REVIEW_TIMEOUT` | `420` | Seconds before a review round is killed |

`MAX_ROUNDS` is passed per-invocation (`--max-rounds N`); the skills default to 5.

## The engine

`bin/kimi-review.sh` runs one review round and prints Kimi's verdict to stdout. It's
copied into each skill folder so every skill is self-contained. The canonical source
is `bin/`; `install.sh` re-syncs the copies.

```
kimi-review.sh --plan-file PLAN.md --round 1 --max-rounds 5
```

Exit codes: `0` ok · `2` bad args · `3` no `kimi` CLI · `4` not logged in · `5` no
plan file · `124` timeout.

## Credits

Built on [Matt Pocock](https://github.com/mattpocock)'s `grill-me` and
`grill-with-docs` skills (MIT) — Act 1 is his work. The adversarial second-model
review (Act 2) is the addition, ported from the OpenAI Codex version to Kimi.

## License

MIT — see [LICENSE](./LICENSE).
