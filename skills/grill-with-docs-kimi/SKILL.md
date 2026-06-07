---
name: grill-with-docs-kimi
description: Two-act planning skill, docs-aware. Act 1 grills you one question at a time AND challenges your plan against the project's CONTEXT.md glossary, sharpening terminology and writing ADRs inline as decisions crystallise. Act 2 hands the locked plan to Kimi, a rival model, which adversarially reviews it over several rounds until both models sign off. Use when stress-testing a plan against your project's documented language and decisions.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# grill-with-docs-kimi

Same two-act structure as `grill-me-kimi`, but Act 1 also challenges your plan
against the existing domain model: it sharpens terminology against `CONTEXT.md`
and records hard-to-reverse decisions as ADRs while you talk. Act 2 is the Kimi
adversarial review loop.

Two artifacts come out: `PLAN.md` (the *what*) and `PLAN-REVIEW-LOG.md` (the
*why* — the round-by-round debate). Plus any `CONTEXT.md` / `docs/adr/` updates
captured inline during Act 1.

---

## Act 1 — Grill, against the docs (lock the plan)

Interview the user relentlessly about every aspect of this plan until you reach a
shared understanding. Walk down each branch of the design tree, resolving
dependencies one-by-one. For each question, provide your recommended answer. Ask
**one at a time**, waiting for feedback. If a question can be answered by exploring
the codebase, explore instead.

### Domain awareness

During exploration, also look for existing docs. Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts; the map
points to where each lives. Create files **lazily** — only when you have something
to write. No `CONTEXT.md`? Create one when the first term is resolved. No
`docs/adr/`? Create it when the first ADR is needed.

### During the session

- **Challenge against the glossary.** When a term conflicts with `CONTEXT.md`, call
  it out: "Your glossary defines 'cancellation' as X, but you seem to mean Y — which?"
- **Sharpen fuzzy language.** Propose a precise canonical term. "You're saying
  'account' — do you mean the Customer or the User? Those are different things."
- **Discuss concrete scenarios.** Invent edge-case scenarios that force precision
  about the boundaries between concepts.
- **Cross-reference with code.** If the user says how something works, check the
  code agrees. Surface contradictions.
- **Update `CONTEXT.md` inline** the moment a term is resolved — don't batch.
  Follow [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md). `CONTEXT.md` is a glossary and
  nothing else: no implementation details, no spec, no scratch pad.
- **Offer ADRs sparingly** — only when all three hold: hard to reverse, surprising
  without context, the result of a real trade-off. Follow [ADR-FORMAT.md](./ADR-FORMAT.md).

When the plan is locked, write it to **`PLAN.md`** (goal, approach, steps, files
touched, decisions + reasoning so Kimi can challenge it) and start
**`PLAN-REVIEW-LOG.md`**.

---

## Act 2 — Kimi adversarial review loop

Identical to `grill-me-kimi`. The bundled engine is at
`~/.claude/skills/grill-with-docs-kimi/kimi-review.sh`.

### Gate 1 — kickoff
Show the locked `PLAN.md` briefly; confirm the user wants the Kimi review. No yes, no proceed.

**Thinking mode.** The engine reads `~/.kimi-grill/thinking` (`on`/`off`, default `on`).
If the file doesn't exist yet, offer a one-time pick — **ON** (deeper, slower) vs **OFF**
(faster) — and write the word to it. Otherwise note the current mode. `KIMI_NO_THINKING=1`
overrides one run.

### The loop (`MAX_ROUNDS = 5`)
For each round `N` from 1:

1. Run Kimi (read-only, repo root):
   ```bash
   ~/.claude/skills/grill-with-docs-kimi/kimi-review.sh --plan-file PLAN.md --round N --max-rounds 5
   ```
   Round 1 is a fresh session; rounds ≥ 2 pass `--continue` so the same Kimi session
   remembers its concerns and checks the revision. Stdout = numbered concerns + a
   final `VERDICT:` line. Tell Kimi to challenge the plan against `CONTEXT.md` too —
   the engine prompt covers codebase contradictions; the glossary is part of that.
2. Append Kimi's full review to `PLAN-REVIEW-LOG.md` under `## Round N — Kimi`.
3. Read the verdict: `APPROVED` → Gate 2; `CHANGES_REQUESTED` → continue.
4. For each concern: fix `PLAN.md` if Kimi is right, or rebut in the log with
   reasoning if it's a trade-off you'd defend. Record what changed.
5. Next round, or stop at `MAX_ROUNDS`.

### Termination
First `VERDICT: APPROVED`, or the cap. If capped without approval, list the open
concerns and let the user decide. Don't pretend it passed.

### Gate 2 — final sign-off
Summarise final `PLAN.md`, round count, resolved vs still-disputed concerns. Explicit
yes **before any implementation code**. Act 2 only reads, reviews, and edits the
plan + docs files — never code.

---

## Notes

- **Auth / cost:** the engine calls the `kimi` CLI; your `kimi login` (OAuth) account
  is used — no API key, no per-token billing. Setup: `brew install kimi-cli && kimi login`.
- **Read-only:** Kimi runs in `--plan` mode scoped to the repo; it cannot write.
- **Model:** plan default; override `KIMI_MODEL=...`, disable thinking `KIMI_NO_THINKING=1`.

Built on Matt Pocock's `grill-with-docs` skill (MIT) — Act 1 is his. The Kimi
adversarial review (Act 2) is the addition; it swaps OpenAI Codex for Kimi.
