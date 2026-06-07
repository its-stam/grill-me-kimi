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

Plus **`kimi-code-review`** — a critical second pair of eyes on a **code diff** (not a
plan), from a different model. Like a Codex review, but on Kimi (OAuth, no API key).
Reviews uncommitted changes, a branch, or a PR read-only and returns severity-tagged
findings + a verdict.

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

## Authentication — login, and re-login when it expires

The engine shells out to `kimi`, so it uses whatever account you logged into. Pure
**OAuth subscription, no API key**. No secret is ever stored in this repo or in the
skill — `kimi` reads your credentials from its own data dir (outside the repo).

**First time:**
```bash
kimi login              # OAuth device flow: opens a URL, sign in with your Kimi account
```

**Token lifetime.** The short-lived access token (~15 min) is refreshed silently in
the background by a longer-lived refresh token — you won't notice. Only when the
refresh token itself expires (days/weeks) does a review start failing.

**Re-login when it expires.** If a review prints `LLM not set` or a `401`:
```bash
kimi login              # same command, redoes the OAuth flow; the skill picks it up automatically
```

**Quick health check** (no real plan needed):
```bash
printf '# test\n' > /tmp/p.md && ~/.claude/skills/grill-me-kimi/kimi-review.sh --plan-file /tmp/p.md
```
A review back = auth is good. `LLM not set` (exit 6) = re-login. On failure the engine
also prints which data dir it read, so you can see where to re-auth.

### Two wrinkles the engine handles for you

- **Where creds live.** A plain install keeps them in `~/.kimi`; a migrated "Kimi
  Code" install keeps them in `~/.kimi-code`. The engine auto-detects `~/.kimi-code`
  and points the CLI at it via `KIMI_SHARE_DIR`. If `kimi login` ever writes somewhere
  else, force it: `KIMI_SHARE_DIR=<that dir> kimi-review.sh ...`.
- **Config skew.** Newer Kimi Code configs carry capability values (e.g. `tool_use`)
  that an older `kimi` build rejects. The engine writes a sanitized copy to
  `~/.kimi-grill/config.toml` and passes it via `--config-file`, leaving your real
  config untouched. The model comes from that config's `default_model`
  (`kimi-for-coding` on the coding plan) — you don't pass `-m`.

## Use a different model (DeepSeek, Qwen, Ollama, ...)

`kimi` is a generic agent harness, so you can run the exact same review loop with a
different model — DeepSeek, Qwen, a local Ollama model, the Moonshot API, Gemini. For
any OpenAI-compatible model it's config-only, no code change. Full recipes in
**[docs/PROVIDERS.md](./docs/PROVIDERS.md)**.

## API fallback (OAuth stays primary)

The engine always tries your **OAuth** login first. If — and only if — that produces
no review (expired login, no model) and an API key is present, it automatically
retries once via an OpenAI-compatible API. OAuth is never bypassed while it works.

The fallback uses the Moonshot API by default (same Kimi model family). It kicks in
when any of `GRILL_KIMI_API_KEY`, `MOONSHOT_API_KEY`, or `KIMI_API_KEY` is set. If you
don't set one, there's no fallback and you just get the `kimi login` prompt.

## Thinking mode (Kimi's reasoning depth)

Kimi has a binary thinking mode (there's no graded low/medium/high effort dial). The
review skills offer a one-time **ON / OFF** pick at kickoff — ON is deeper and slower,
OFF is faster — and remember it in `~/.kimi-grill/thinking`. Set once, navigate with
the arrow keys, done. Re-pick anytime by asking. Precedence:
`KIMI_NO_THINKING=1` (per run) > `~/.kimi-grill/thinking` (`on`/`off`) > on (default).

## Configuration

| Env var | Default | Effect |
|---|---|---|
| `KIMI_SHARE_DIR` | `~/.kimi-code` if present, else `~/.kimi` | Kimi data dir (OAuth creds + config) |
| `KIMI_MODEL` | the config's `default_model` | Pin a model alias from that config's `[models]` |
| `KIMI_NO_THINKING` | unset (thinking on) | Set to `1` to disable Kimi's thinking mode |
| `KIMI_REVIEW_TIMEOUT` | `420` | Seconds before a review round is killed |
| `MOONSHOT_API_KEY` / `GRILL_KIMI_API_KEY` | unset | API key for the fallback (used only if OAuth fails) |
| `GRILL_KIMI_BASE_URL` | `https://api.moonshot.ai/v1` | API fallback endpoint |
| `GRILL_KIMI_MODEL` | `kimi-k2.6` | API fallback model |

`MAX_ROUNDS` is passed per-invocation (`--max-rounds N`); the skills default to 5.

## Updating Kimi

Three layers, three answers:

- **The model** — mostly automatic. The skills don't pin a model; they use the
  config's `default_model` (`kimi-for-coding`), a *role alias* that Moonshot maps
  server-side to its current coding model. New/better models usually arrive with no
  action. To pin a specific one, set `KIMI_MODEL=<alias>` (no code change).
- **The CLI** — manual: `brew upgrade kimi-cli` (or the code.kimi.com installer). New
  versions add models, flags, and capabilities. (An older CLI is also why the engine
  sanitizes the config — see *Two wrinkles* above; upgrading eventually removes the need.)
- **These skills** — nothing to do. They're model-agnostic, so a new Kimi version
  (2.7, 3.0, …) needs no change here.

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
