---
name: grill-me-kimi
description: Two-act planning skill. Act 1 interrogates you one question at a time until the plan is locked. Act 2 hands that plan to Kimi (a rival model) which adversarially tears it apart over several rounds until both models sign off — before a line of code is written. Use when you want a plan stress-tested by you AND a second model. Triggers "grill me kimi", "grill and review", "harden this plan".
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

**Act 1** grills you to lock the plan. **Act 2** hands that plan to Kimi, a rival
model running under your own OAuth login, which adversarially reviews it over
several rounds until both models sign off. Only then do you write code.

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

### The loop

`MAX_ROUNDS = 5` (override if the user asks). The review engine is bundled with
this skill at `~/.claude/skills/grill-me-kimi/kimi-review.sh`.

For each round `N` from 1:

1. **Run Kimi** (read-only, in the repo root):

   ```bash
   ~/.claude/skills/grill-me-kimi/kimi-review.sh --plan-file PLAN.md --round N --max-rounds 5
   ```

   Round 1 starts a fresh Kimi session. Rounds ≥ 2 automatically pass `--continue`,
   so the **same** Kimi session re-reads the revised plan and remembers the concerns
   it raised. The script prints Kimi's review (numbered concerns + a final
   `VERDICT:` line) to stdout.

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

- **Auth / cost:** the script calls the `kimi` CLI, which uses whatever login you
  set up. If you ran `kimi login` (OAuth), reviews run on that account — no API key,
  no per-token billing. First-time setup: `brew install kimi-cli && kimi login`.
- **Read-only safety:** Kimi runs in `--plan` mode scoped to the repo; it cannot
  modify files. It reads `PLAN.md` and the codebase, nothing more.
- **Model & creds:** the engine auto-detects your Kimi data dir (`~/.kimi-code` or
  `~/.kimi`) and uses that config's `default_model` (`kimi-for-coding` on the coding
  plan) — no `-m` needed. Override with `KIMI_MODEL=...`. Disable thinking with
  `KIMI_NO_THINKING=1`. See the repo README for the auth details.
- **If the script errors:** exit 3 = install the CLI, exit 4 = run `kimi login`,
  exit 124 = timeout (raise `--timeout` or `KIMI_REVIEW_TIMEOUT`).

Built on Matt Pocock's `grill-me` / `grill-with-docs` skills (MIT) — Act 1 is his.
The Kimi adversarial review (Act 2) is the addition; it swaps OpenAI Codex for Kimi.
