---
name: kimi-review
description: Act 2 only — you already have a plan. Hands a written plan to a configured second model (Kimi is one option among several — see docs/PROVIDERS.md) which adversarially reviews it read-only over several rounds until APPROVED or a round cap. Use when you have a PLAN.md (or any plan/spec/design doc) and want an independent second model to tear it apart before you build. Triggers "kimi review", "review my plan with kimi", "second opinion on this plan".
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

Confirm the user wants to start the review of `<plan-file>`. No yes, no proceed.

**Reviewer setup.** No default provider is configured. Confirm `KIMI_REVIEW_CMD`
or `KIMI_REVIEW_BASE_URL`/`_MODEL`/`_API_KEY` is set — see
[docs/PROVIDERS.md](../../docs/PROVIDERS.md) for recipes (Kimi via its CLI or the
Moonshot API, DeepSeek, Qwen, Ollama, ...). Unset, the engine aborts naming the
three generic variables; surface that to the user before proceeding.

## The loop

`MAX_ROUNDS = 3` (override on request, or `MAX_ROUNDS=N` in the environment).
Engine bundled at `~/.claude/skills/kimi-review/kimi-review.sh`.

For each round `N` from 1:

1. **Run the reviewer** (read-only, repo root):
   ```bash
   ~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round N --max-rounds 3
   ```
   Round 1 is fresh; whether round ≥ 2 resumes the same session depends on the
   configured `KIMI_REVIEW_CMD` (the Kimi-CLI recipe passes `--continue`). Stdout =
   numbered concerns + a final `VERDICT:` line.
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

- **No default provider.** See [docs/PROVIDERS.md](../../docs/PROVIDERS.md).
- **Read-only:** enforced by `bin/kimi-loop.sh`, which hashes the plan file before
  round 1 and after every round and aborts on a mismatch.
- **Errors:** exit 5 = plan file not found, 6 = reviewer command failed or produced
  no output, 7 = no reviewer configured, 124 = timeout.

Part of the grill-me-kimi family. Built on the idea behind Matt Pocock's grill
skills (MIT); swaps OpenAI Codex for Kimi as the second model.
