---
name: grill-me-kimi
description: Two-act planning skill. Act 1 interrogates you one question at a time until the plan is locked. Act 2 hands that plan to a configured second model (Kimi is one option among several — see docs/PROVIDERS.md) which adversarially tears it apart over several rounds until both models sign off — before a line of code is written. Use when you want a plan stress-tested by you AND a second model. Triggers "grill me kimi", "grill and review", "harden this plan".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# grill-me-kimi

Two AI models harden your plan before you write a line of code.

There are two gaps in AI-assisted coding: the gap between **you and Claude** (do
we agree on what to build?), and the gap between **Claude and the quality of what
it produces** (is the plan actually correct — and how would you, a non-expert,
know?). The same model that plans the build is a poor judge of its own plan; it's
an echo chamber. A different provider catches what Claude misses.

**Act 1** grills you to lock the plan. **Act 2** hands that plan to Kimi (or any
other second model you configure) which adversarially reviews it over several
rounds until both models sign off. Only then do you write code.

You gate twice: at kickoff, and at final sign-off. Kimi is read-only the whole time.

Two artifacts come out: `PLAN.md` (the clean final plan — the *what*) and
`PLAN-REVIEW-LOG.md` (the round-by-round debate — the *why*).

---

## Act 1 — Grill the user (lock the plan)

Interview the user relentlessly about every aspect of this plan until you reach a
shared understanding. Walk down each branch of the design tree, resolving
dependencies between decisions one-by-one. For each question, provide your
recommended answer.

- Ask the questions **one at a time**, waiting for feedback on each before continuing.
- If a question can be answered by exploring the codebase, **explore the codebase
  instead** of asking.
- Keep going until the decision tree is resolved — no hand-wavy branches left.

When the plan is locked, write it to **`PLAN.md`** in the repo root: the goal, the
approach, the concrete steps, the files touched, and the decisions made (with the
reasoning, so Kimi can challenge it). Then start **`PLAN-REVIEW-LOG.md`** with a
short header and the locked plan's date.

---

## Act 2 — Kimi adversarial review loop

### Gate 1 — kickoff

Show the user the locked `PLAN.md` in one or two sentences and confirm they want to
start the Kimi review. Do not proceed without a yes.

**Reviewer setup.** The engine has no default provider — confirm `KIMI_REVIEW_CMD`
or `KIMI_REVIEW_BASE_URL`/`_MODEL`/`_API_KEY` is set (see
[docs/PROVIDERS.md](../../docs/PROVIDERS.md) for recipes, including Kimi via its
CLI or the Moonshot API). If none is set, the engine aborts naming the three
generic variables — tell the user and offer the recipe before proceeding.

### The loop

`MAX_ROUNDS = 3` (override if the user asks, or by exporting `MAX_ROUNDS`). The
review engine is bundled with this skill at
`~/.claude/skills/grill-me-kimi/kimi-review.sh`.

For each round `N` from 1:

1. **Run the reviewer** (read-only, in the repo root):

   ```bash
   ~/.claude/skills/grill-me-kimi/kimi-review.sh --plan-file PLAN.md --round N --max-rounds 3
   ```

   Round 1 starts fresh. Whether round ≥ 2 resumes the same session (so the reviewer
   remembers earlier concerns) depends on the configured `KIMI_REVIEW_CMD` — the
   Kimi-CLI recipe in docs/PROVIDERS.md passes `--continue` for that. The script
   prints the review (numbered concerns + a final `VERDICT:` line) to stdout.

2. **Append Kimi's full review** to `PLAN-REVIEW-LOG.md` under a `## Round N — Kimi`
   heading. Never paraphrase it away — the log is the audit trail.

3. **Read the verdict line:**
   - `VERDICT: APPROVED` → the loop is done. Go to Gate 2.
   - `VERDICT: CHANGES_REQUESTED` → continue.

4. **Respond to each concern.** For every `[BLOCKER]`/`[MAJOR]`/`[MINOR]`:
   - If Kimi is right: revise `PLAN.md` to fix it.
   - If Kimi is wrong or it's a trade-off you'd defend: do **not** blindly change
     the plan. Write your rebuttal in `PLAN-REVIEW-LOG.md` under `### Claude's
     response (Round N)` with the reasoning, and carry it into the next round so
     Kimi can reconsider. The point is the best plan, not appeasing the reviewer.
   - Record what you changed under the same heading.

5. **Next round**, or stop if `N == MAX_ROUNDS`.

### Termination

Stop on the first `VERDICT: APPROVED`, or when `N` hits `MAX_ROUNDS`. If the cap is
hit without approval, say so plainly: list the concerns still open and let the user
decide whether to proceed, do another round, or rethink. Do not pretend it passed.

### Gate 2 — final sign-off

Summarise for the user: the final `PLAN.md`, how many rounds it took, and the
concerns that were resolved vs any the two models still disagree on. Get an explicit
yes **before writing any implementation code**. Act 2 never writes code — it only
reads, reviews, and edits the two plan files.

---

## Notes

- **No default provider.** Configure `KIMI_REVIEW_CMD` (e.g. the `kimi` CLI on
  your OAuth login) or the generic `KIMI_REVIEW_BASE_URL`/`_MODEL`/`_API_KEY` —
  see [docs/PROVIDERS.md](../../docs/PROVIDERS.md).
- **Read-only safety:** the loop driver (`bin/kimi-loop.sh`) hashes `PLAN.md`
  before round 1 and after every round and aborts if it changed — enforced, not
  just asked for in the prompt.
- **If the script errors:** exit 5 = plan file not found, 6 = reviewer command
  failed or produced no output, 7 = no reviewer configured, 124 = timeout (raise
  `--timeout` or `KIMI_REVIEW_TIMEOUT`).

Built on Matt Pocock's `grill-me` / `grill-with-docs` skills (MIT) — Act 1 is his.
The Kimi adversarial review (Act 2) is the addition; it swaps OpenAI Codex for Kimi.
