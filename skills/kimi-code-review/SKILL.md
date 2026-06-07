---
name: kimi-code-review
description: A critical second pair of eyes on your code — from a different model. Hands a code diff to Kimi (via your OAuth login, no API key), which adversarially reviews it read-only and returns severity-tagged findings with a verdict. Like a Codex review, but on Kimi. Use when you want an independent model to review uncommitted changes, a branch, or a PR before you merge. Triggers "kimi code review", "review my code with kimi", "second opinion on this diff".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# kimi-code-review

A critical code review from a **different model**. Claude reviewing Claude's code is
an echo chamber; Kimi is a different provider, so it catches what Claude misses. It
reviews your diff read-only and returns numbered findings (`[BLOCKER]`/`[MAJOR]`/
`[MINOR]`) ending in `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.

Runs on your Kimi **OAuth subscription** — no API key. Same engine as the rest of the
family (`kimi-review.sh`, here in `~/.claude/skills/kimi-code-review/`), in code mode.

---

## Step 1 — decide what to review

Pick the diff, in this order unless the user says otherwise:

- **Uncommitted work** (default): `git diff` (unstaged) + `git diff --staged`.
- **Staged only:** `git diff --staged`.
- **A branch / PR:** `git diff <base>...HEAD` (e.g. `git diff main...HEAD`).
- **Specific files:** `git diff -- <paths>`.

Capture it to a temp file and confirm it's non-empty:

```bash
git diff HEAD > /tmp/kimi-review.diff   # or the range/paths chosen above
[ -s /tmp/kimi-review.diff ] || echo "No changes to review."
```

If there are no changes, say so and stop. If the diff is huge (say > 4000 lines),
tell the user and offer to review per-area (split by path) instead of all at once.

## Step 2 — kickoff

Tell the user what you're about to review (e.g. "12 files, ~300 lines, on top of
`main`") and confirm. Start a `CODE-REVIEW-LOG.md` for the audit trail.

**Thinking mode.** The engine reads `~/.kimi-grill/thinking` (`on`/`off`, default `on`).
If the file doesn't exist yet, offer a one-time pick — **ON** (deeper, slower) vs **OFF**
(faster) — and write the word to it. Otherwise note the current mode. `KIMI_NO_THINKING=1`
overrides one run.

## Step 3 — run the review

```bash
~/.claude/skills/kimi-code-review/kimi-review.sh \
  --mode code --diff-file /tmp/kimi-review.diff --repo "$(git rev-parse --show-toplevel)" --round 1
```

Kimi reads the diff plus the full files in the repo (read-only) and prints findings +
a `VERDICT:` line. Append its full output to `CODE-REVIEW-LOG.md` under `## Round 1 — Kimi`.

## Step 4 — triage the findings

Go through each finding with the user:

- **`[BLOCKER]`/`[MAJOR]`:** real bug → fix it (or surface it for the user to fix). If
  you disagree, say why; don't fix on autopilot.
- **`[MINOR]`:** note it; fix if cheap.
- For anything you're unsure Kimi got right, verify against the actual code before acting.

This skill may edit code to apply agreed fixes (unlike the plan-review skills, which
only touch plan files). Make each fix deliberately, not in bulk.

## Step 5 (optional) — re-review after fixes

If you changed code in response, regenerate the diff and run round 2 — the same Kimi
session remembers its findings and checks whether they're addressed:

```bash
git diff HEAD > /tmp/kimi-review.diff
~/.claude/skills/kimi-code-review/kimi-review.sh \
  --mode code --diff-file /tmp/kimi-review.diff --repo "$(git rev-parse --show-toplevel)" --round 2
```

Append to the log. Stop on `VERDICT: APPROVED`, when the user is satisfied, or at
`--max-rounds` (default 5).

---

## Notes

- **A different model on purpose.** If Claude wrote the code, a Kimi review is the
  point. For a Claude-side review of the diff, use `/code-review` instead.
- **Read-only:** Kimi runs in `--plan` mode scoped to the repo; it cannot modify
  files. Any fixes are made by you/Claude, not Kimi.
- **Auth / model / fallback:** identical to the rest of the family — OAuth first (no
  API key), optional API fallback if a key is set. See the repo README and
  `docs/PROVIDERS.md` (e.g. review with DeepSeek or a local Ollama model instead).
- **Errors:** exit 3 = install `kimi`, 4 = `kimi login`, 5 = diff file missing/empty,
  6 = no review produced (re-login), 124 = timeout.
