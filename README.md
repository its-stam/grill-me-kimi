# grill-me-kimi

Two AI models harden your plan before you write a line of code: one grills you
until the plan is locked, the second tears it apart read-only, round after round,
until it signs off or you hit the round cap and decide yourself.

## Results (from `./test.sh`)

| Check | Result |
|---|---|
| Mock reviewer that objects twice, then approves | approved after **round 3 of 3** |
| Mock reviewer that never approves | stops at the **round cap (3)**, exits non-zero, prints the open `[BLOCKER]`/`[MAJOR]` concerns |
| Mock reviewer that edits the file it's reviewing | loop **aborts on the hash mismatch**, exits non-zero, before trusting its output |
| No provider configured | engine **aborts**, exit non-zero, naming the three env vars needed |
| Full suite | **36 assertions, 0 failed** |

Run it yourself: `./test.sh` (no network, no real model — everything above runs
against `tests/mock-reviewer.sh`).

## The skills

| Skill | Act 1 | Act 2 |
|---|---|---|
| `grill-me-kimi` | Claude interrogates you one question at a time until the decision tree is resolved | Adversarial review loop |
| `grill-with-docs-kimi` | Same, but challenges your plan against your project's `CONTEXT.md` glossary + writes ADRs inline | Review loop |
| `kimi-review` | — (you already have a plan) | Review loop |
| `kimi-code-review` | — (you already have a diff) | Review of a code diff, not a plan |

"Kimi" names the family; the reviewer itself is whatever you configure (see
Provider below) — Kimi is one supported option, not the only one.

## How the loop works

1. Claude writes the locked plan to `PLAN.md` and starts `PLAN-REVIEW-LOG.md`.
2. **Round 1:** the reviewer reads the plan and the codebase read-only and returns
   numbered `[BLOCKER]`/`[MAJOR]`/`[MINOR]` concerns, ending in
   `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.
3. **Rounds 2..N:** Claude revises the plan (or rebuts in the log) between rounds;
   the reviewer re-reads it and, for each earlier concern, says ADDRESSED /
   PARTIALLY / NOT ADDRESSED, plus anything new.
4. Bounded by `MAX_ROUNDS` (default **3**, override with the env var or
   `--max-rounds`). Terminates on `APPROVED` or the cap — capped without approval
   means you decide: another round, proceed anyway, or rethink.
5. You gate twice: kickoff, and final sign-off before any code.

Two scripts implement this: `bin/kimi-review.sh` runs one round and prints the
verdict; `bin/kimi-loop.sh` drives the whole loop unattended (round bookkeeping,
the read-only hash check, the cap, the escalation list) and is what `test.sh`
exercises. The interactive skills mostly call `kimi-review.sh` round-by-round
themselves, since a real Act 2 run needs an editor — Claude — reading each round's
concerns and revising the plan in between.

## Provider — no default

There is no built-in reviewer. Configure one of:

- `KIMI_REVIEW_CMD` — any command (the `kimi` CLI, `codex`, a script).
- `KIMI_REVIEW_BASE_URL` + `KIMI_REVIEW_MODEL` + `KIMI_REVIEW_API_KEY` — a generic
  OpenAI-compatible endpoint, called in-process, no CLI needed.

Neither set, and the engine aborts naming those three variables. Full recipes —
Kimi (CLI or API), DeepSeek, Qwen, local Ollama, others — in
**[docs/PROVIDERS.md](./docs/PROVIDERS.md)**.

## Install

```bash
./install.sh            # copies skills/* into ~/.claude/skills/, incl. the engine
```

Or manually:

```bash
cp -r skills/* ~/.claude/skills/
chmod +x ~/.claude/skills/*/kimi-review.sh
```

Then set a reviewer (see Provider above) and in Claude Code: `/grill-me-kimi`,
`/grill-with-docs-kimi`, `/kimi-review`, or `/kimi-code-review`.

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `KIMI_REVIEW_CMD` | unset | Reviewer command; reads `$GRILL_REVIEW_PROMPT_FILE`, prints the review |
| `KIMI_REVIEW_BASE_URL` / `_MODEL` / `_API_KEY` | unset | Generic OpenAI-compatible reviewer, no CLI |
| `MAX_ROUNDS` | `3` | Round cap for `bin/kimi-loop.sh` (or pass `--max-rounds`) |
| `KIMI_REVIEW_TIMEOUT` | `420` | Seconds before a round is killed |

## The engine

`bin/kimi-review.sh` runs one review round; `bin/kimi-loop.sh` runs the whole
loop. `skills/*/kimi-review.sh` are symlinks to `bin/kimi-review.sh` — one
canonical script, so the four skills can't drift out of sync with each other.
`install.sh` materializes a real file at each installed location, since a
symlink doesn't survive being copied where `bin/` isn't alongside it.

Exit codes: `0` ok (or approved, for the loop) · `2` bad args · `5` no plan/diff
file · `6` reviewer command failed or produced no output · `7` no reviewer
configured · `8` read-only violation (loop only) · `9` capped without approval
(loop only) · `124` timeout.

More detail — Kimi-specific auth/update notes, why there's no default provider,
credits, license — in [docs/NOTES.md](./docs/NOTES.md).
