---
name: kimi-review
description: Act 2 only — you already have a plan. Hands a written plan to Kimi, a rival model running under your OAuth login, which adversarially reviews it read-only over several rounds until APPROVED or a round cap. Use when you have a PLAN.md (or any plan/spec/design doc) and want an independent second model to tear it apart before you build. Triggers "kimi review", "review my plan with kimi", "second opinion on this plan".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# kimi-review

The adversarial review loop from `grill-me-kimi`, standalone — for when the plan
already exists and you just want a rival model to harden it.

The same model that writes a plan is a poor judge of it. Kimi is a different
provider, so it catches what Claude misses. It reviews read-only, over several
rounds, remembering its own concerns between rounds, until it signs off or a round
cap is hit. You gate twice: kickoff, and final sign-off before any code.

---

## Step 0 — locate the plan

Find the plan to review. Default `PLAN.md` in the repo root. If the user points at
another file (a spec, a design doc, an issue), use that as `--plan-file`. If no plan
file exists, ask the user to point at one, or offer to run `grill-me-kimi` to build
one first. Start (or append to) `PLAN-REVIEW-LOG.md` for the audit trail.

## Gate 1 — kickoff

Confirm the user wants to start the Kimi review of `<plan-file>`. No yes, no proceed.

## The loop

`MAX_ROUNDS = 5` (override on request). Engine bundled at
`~/.claude/skills/kimi-review/kimi-review.sh`.

For each round `N` from 1:

1. **Run Kimi** (read-only, repo root):
   ```bash
   ~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round N --max-rounds 5
   ```
   Round 1 is fresh; rounds ≥ 2 auto-pass `--continue` so the same Kimi session
   re-reads the revised plan and remembers its prior concerns. Stdout = numbered
   concerns + a final `VERDICT:` line.
2. **Append** Kimi's full review to `PLAN-REVIEW-LOG.md` under `## Round N — Kimi`.
3. **Read the verdict:** `VERDICT: APPROVED` → Gate 2. `VERDICT: CHANGES_REQUESTED` → continue.
4. **Respond to each concern.** Fix the plan file if Kimi is right; rebut in the log
   with reasoning if it's a trade-off you'd defend (carry the rebuttal into the next
   round so Kimi can reconsider). Record what changed.
5. **Next round**, or stop at `MAX_ROUNDS`.

## Termination

First `VERDICT: APPROVED`, or the cap. If capped without approval, list the open
concerns plainly and let the user decide: another round, proceed anyway, or rethink.
Don't claim it passed when it didn't.

## Gate 2 — final sign-off

Summarise: final plan, round count, resolved vs still-disputed concerns. Explicit yes
**before any implementation code**. This skill only reads, reviews, and edits the plan
file + the log — never code.

---

## Notes

- **Auth / cost:** the engine calls the `kimi` CLI; your `kimi login` (OAuth) account
  is used — no API key, no per-token billing. Setup: `brew install kimi-cli && kimi login`.
- **Read-only:** Kimi runs in `--plan` mode scoped to the repo; it cannot write.
- **Model:** plan default; override `KIMI_MODEL=...`, disable thinking `KIMI_NO_THINKING=1`.
- **Errors:** exit 3 = install CLI, 4 = `kimi login`, 5 = plan file not found, 124 = timeout.

Part of the grill-me-kimi family. Built on the idea behind Matt Pocock's grill
skills (MIT); swaps OpenAI Codex for Kimi as the second model.
