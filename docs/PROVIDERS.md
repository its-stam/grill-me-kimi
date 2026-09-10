# Which second model

There is no default provider. The engine (`bin/kimi-review.sh`) is configured with
one of two things, checked in this order:

1. **`KIMI_REVIEW_CMD`** — any command. It reads the prompt from the file named in
   `$GRILL_REVIEW_PROMPT_FILE` (also exported: `$GRILL_REVIEW_ROUND`,
   `$GRILL_REVIEW_MAX_ROUNDS`, `$GRILL_REVIEW_MODE`, `$GRILL_REVIEW_PLAN_FILE`,
   `$GRILL_REVIEW_REPO_DIR`) and prints the review to stdout. This is how you wire
   up the `kimi` CLI, `codex`, a local script, or a test double — see the Kimi
   recipe below and `tests/mock-reviewer.sh` for a worked example.
2. **`KIMI_REVIEW_BASE_URL`, `KIMI_REVIEW_MODEL`, `KIMI_REVIEW_API_KEY`** — a
   generic OpenAI-compatible Chat Completions endpoint (base URL + model name +
   key), called in-process with Python's standard library. No CLI, no config file,
   no new dependency.

Set neither, and the engine aborts naming exactly these three variables (the
Kimi-CLI route above is a `KIMI_REVIEW_CMD`, not a third alternative, so it's not
named in that message).

**Kimi is one documented option among several**, not the hardcoded reviewer. Its
availability depends on your own OAuth login or API key, same as any other
provider here.

> Secrets rule: an API key for any of these is a secret. Put it in an
> **environment variable**, never in this repo. Nothing in this repo contains a
> key, and it should stay that way.

---

## Recipe: Kimi, via the CLI (OAuth or API key)

```bash
kimi login   # one-time OAuth device flow — no key needed after this
```

```bash
export KIMI_REVIEW_CMD='kimi --output-format text -p "$(cat "$GRILL_REVIEW_PROMPT_FILE")"'
~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round 1
```

For round `N >= 2`, add `--continue` so the same session remembers its earlier
concerns:

```bash
export KIMI_REVIEW_CMD='kimi --output-format text $( [ "$GRILL_REVIEW_ROUND" -ge 2 ] && echo --continue ) -p "$(cat "$GRILL_REVIEW_PROMPT_FILE")"'
```

Pin a model with `-m <alias>` inside the command, or leave it out to use the
config's `default_model`. `bin/kimi-loop.sh` calls the engine the same way each
round, so the same `KIMI_REVIEW_CMD` works there too.

Verified against the installed `kimi` 0.33.0 (`kimi --help`): `-p`/`--prompt`,
`--output-format`, `-m`/`--model`, `-c`/`--continue` all exist as used above.
`--plan` also still exists, but `kimi --plan -p "..."` errors with `Cannot
combine --prompt with --plan.` — that's why this recipe doesn't use it; read-only
is enforced by the prompt instruction plus `bin/kimi-loop.sh`'s hash check
instead (see "The only contract that matters" below), not by a CLI sandbox mode.

### Authentication — login, and re-login when it expires

The `kimi` CLI in the recipe above uses whatever account you logged into with
`kimi login` — OAuth device flow, no API key, no secret stored in this repo.
The short-lived access token (~15 min) refreshes silently via a longer-lived
refresh token; only when that itself expires (days/weeks) does a review start
failing (`kimi` then errors instead of returning a review, and the engine's exit
6 covers that — see "The only contract that matters" below). Re-run
`kimi login` and it picks the new token straight back up.

**Dropped:** the engine no longer auto-detects the Kimi data dir
(`~/.kimi`/`~/.kimi-code` via `KIMI_SHARE_DIR`) or sanitizes `config.toml` for an
older CLI build (writing to `~/.kimi-grill/config.toml`, passed via
`--config-file`). Both were workarounds for a specific `kimi` CLI version; the
engine doesn't invoke `kimi` at all anymore, `KIMI_REVIEW_CMD` does, so any such
CLI-version quirk is now the recipe's problem to solve (e.g. by pointing
`KIMI_SHARE_DIR` inside your own `KIMI_REVIEW_CMD` string), not the engine's.

### API fallback (OAuth stays primary)

**Dropped.** Earlier versions tried the OAuth path first and, only if that
produced no review, automatically retried once via an API key
(`GRILL_KIMI_API_KEY`/`MOONSHOT_API_KEY`/`KIMI_API_KEY`, default
`https://api.moonshot.ai/v1`). The engine now resolves exactly one reviewer per
run (`KIMI_REVIEW_CMD`, else the three generic variables, else abort) — no
two-step try-then-fall-back inside a single call. Want the same effect? Put the
fallback logic in your own `KIMI_REVIEW_CMD` script, or use the Moonshot API
recipe below directly instead of the OAuth one.

### Thinking mode (Kimi's reasoning depth)

**Dropped.** `kimi --help` (0.33.0) has no `--thinking` flag — it was removed
from the CLI (this repo used to also persist a picked on/off state to
`~/.kimi-grill/thinking`, honored via `KIMI_NO_THINKING`). If a future `kimi`
version re-adds reasoning-depth control, set it inside your `KIMI_REVIEW_CMD`
string the same way you'd set `-m`.

## Recipe: Kimi, via the Moonshot API (no CLI, no OAuth)

Moonshot's API is OpenAI-compatible, so this needs no `KIMI_REVIEW_CMD` at all —
just the three generic variables:

```bash
export KIMI_REVIEW_BASE_URL="https://api.moonshot.ai/v1"
export KIMI_REVIEW_MODEL="kimi-k2.7"          # check current model ids in Moonshot's docs
export KIMI_REVIEW_API_KEY="$MOONSHOT_API_KEY"
~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round 1
```

## Use a different model (DeepSeek, Qwen, Ollama, ...)

Any OpenAI-compatible endpoint works with the same three generic variables — no
code change, no per-provider recipe needed beyond the base URL, model id, and
key.

### Recipe: DeepSeek

```bash
export KIMI_REVIEW_BASE_URL="https://api.deepseek.com/v1"
export KIMI_REVIEW_MODEL="deepseek-reasoner"   # or deepseek-chat
export KIMI_REVIEW_API_KEY="$DEEPSEEK_API_KEY"
```

### Recipe: Qwen (Alibaba DashScope, OpenAI-compatible)

```bash
export KIMI_REVIEW_BASE_URL="https://dashscope-intl.aliyuncs.com/compatible-mode/v1"   # .cn for China
export KIMI_REVIEW_MODEL="qwen-max"            # or qwen-plus, qwen3-coder-plus, ...
export KIMI_REVIEW_API_KEY="$DASHSCOPE_API_KEY"
```

### Recipe: local model via Ollama (free, offline)

```bash
export KIMI_REVIEW_BASE_URL="http://localhost:11434/v1"
export KIMI_REVIEW_MODEL="qwen2.5-coder:14b"   # whatever you've pulled
export KIMI_REVIEW_API_KEY="ollama"            # any non-empty dummy
```

## Claude or Gemini as the reviewer

Possible — Gemini's OpenAI-compatible endpoint works with the generic variables
above; Claude needs a `KIMI_REVIEW_CMD` wrapping a small script (the Messages API
isn't Chat-Completions-shaped). But note the whole point of this review is a
*different* provider than the one that wrote the plan. If Claude wrote the plan,
reviewing with Claude is the echo chamber this exists to avoid. Prefer a
non-Claude reviewer.

---

## The only contract that matters

Whatever you configure, the reviewer command or endpoint must:

1. Read the prompt (from `$GRILL_REVIEW_PROMPT_FILE` for `KIMI_REVIEW_CMD`) and the
   repo **read-only**, and print its review to stdout.
2. End with a single line: `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.

`bin/kimi-loop.sh` enforces read-only itself — it hashes the reviewed file before
round 1 and after every round, and aborts if it changed — so a reviewer that
ignores the "don't write" instruction is caught, not just asked nicely.
