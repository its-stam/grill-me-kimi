# Extra detail (moved out of README to keep it short)

## How Act 2 works

1. Claude writes the locked plan to `PLAN.md` and starts a log at `PLAN-REVIEW-LOG.md`.
2. **Round 1:** the reviewer reads the plan read-only and returns numbered
   concerns ending in `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.
3. **Rounds 2..N:** Claude revises the plan (or rebuts in the log); whether the
   *same* reviewer session is resumed depends on `KIMI_REVIEW_CMD` (the Kimi-CLI
   recipe passes `--continue` for that) — the engine itself is stateless between
   rounds.
4. Bounded by `MAX_ROUNDS` (default **3**, was 5). Terminates on `APPROVED` or the cap.
5. You gate twice only: kickoff, and final sign-off before any code.

Read-only used to mean "Kimi runs in `--plan` mode" — dropped, because `--plan`
can't be combined with `-p`/`--prompt` (verified: `kimi --plan -p "..."` →
`Cannot combine --prompt with --plan.`). Read-only is now a prompt instruction
plus an enforced check: `bin/kimi-loop.sh` hashes the file under review before
round 1 and after every round and aborts on a mismatch (see "Why the loop needs
a real driver" below).

## Why Kimi (and not the OpenAI Codex original)?

This is a port of the `grill-me-codex` idea, originally to Kimi specifically.
Kimi's Chat-Completions-compatible API and CLI made it a reasonable first
target: log in once (`kimi login`, OAuth) and reviews run on that subscription,
no per-token billing, no key to manage.

It's no longer the *only* target — swapping in a different model is now a one
env-var change (`KIMI_REVIEW_CMD`, or the three generic `KIMI_REVIEW_BASE_URL`/
`_MODEL`/`_API_KEY` variables), not a one-line code edit in `bin/kimi-review.sh`
the way it used to be. See [PROVIDERS.md](./PROVIDERS.md) ("Which second
model") for the full recipe list.

## Credits

Built on [Matt Pocock](https://github.com/mattpocock)'s `grill-me` and
`grill-with-docs` skills (MIT) — Act 1 is his work. The adversarial second-model
review (Act 2) is the addition, ported from the OpenAI Codex version to run
against any configured second model, with Kimi as one documented option.

## License

MIT — see [LICENSE](../LICENSE).

## Updating Kimi

Three layers, three answers — unchanged in spirit, only "these skills" changed:

- **The model** — mostly automatic if your `KIMI_REVIEW_CMD` doesn't pin one
  (leave out `-m`): the CLI config's `default_model` is a role alias Moonshot
  maps server-side to its current coding model. Pin a specific one with
  `-m <alias>` inside `KIMI_REVIEW_CMD`.
- **The CLI** — manual: `brew upgrade kimi-cli` (or the installer at
  https://github.com/MoonshotAI/kimi-cli). New versions add or remove flags —
  the "Dropped" notes in [PROVIDERS.md](./PROVIDERS.md) exist because of exactly
  that (`--plan`+`-p`, `--thinking`, `--config-file`/`--quiet`/`--work-dir`
  across the CLI's 0.11.0 → 0.33.0 span).
- **These skills / the engine** — nothing to do for a new Kimi model version.
  It changed once, from being hardcoded, to configuring `KIMI_REVIEW_CMD` — a
  new Kimi release doesn't need a repo change, only a CLI upgrade.

## Kimi specifics, if you configure it as your reviewer

Kimi is not the default anymore (see [PROVIDERS.md](./PROVIDERS.md)), but it's the
best-supported recipe. If you wire it up via `KIMI_REVIEW_CMD`:

- **Auth.** The `kimi` CLI logs in with `kimi login` (OAuth device flow) or an API
  key in its own config. Neither is stored in this repo.
- **Updating the model.** Mostly automatic — the recipe doesn't pin a model; it
  uses the CLI config's `default_model` (a role alias Moonshot maps server-side to
  its current coding model). Pin one with `-m <alias>` inside `KIMI_REVIEW_CMD`.
- **Updating the CLI.** Manual: `brew upgrade kimi-cli` (or the installer at
  https://github.com/MoonshotAI/kimi-cli). This repo has no dependency on a
  specific CLI version beyond the `-p`/`--prompt`, `--output-format`, `-m`,
  `--continue` flags the recipe uses.
- **Health check** (no real plan needed):
  ```bash
  printf '# test\n' > /tmp/p.md
  KIMI_REVIEW_CMD='kimi --output-format text -p "$(cat "$GRILL_REVIEW_PROMPT_FILE")"' \
    ~/.claude/skills/kimi-review/kimi-review.sh --plan-file /tmp/p.md
  ```
  A review back = your Kimi login is good.

## Why not a fixed default provider

Earlier versions of this repo shelled out to the `kimi` CLI directly, with an
OAuth-first / API-key-fallback chain built into the engine. That tied the whole
family to one provider's CLI flags, which drifted out from under three of the four
skills as the CLI changed versions, and made every recipe in this doc a special
case. The engine now knows one thing: run a command, or call a generic
OpenAI-compatible endpoint. Kimi is a recipe against that contract, not a
privileged path through the code.

## Why the loop needs a real driver, not just a prompt instruction

`bin/kimi-loop.sh` exists because "the reviewer promised not to write files" isn't
a proof. It hashes the file under review before round 1 and after every round and
aborts the instant that hash changes — this is what `tests/mock-reviewer.sh`'s
`MOCK_REVIEWER_MODE=mutate-plan` exercises in `test.sh`. In real Act 2 usage
(Claude editing `PLAN.md` between rounds), the interactive per-round flow in each
`SKILL.md` is what actually runs; `kimi-loop.sh` is the automatable, testable
version of the same contract, useful on its own for a frozen plan or diff that
won't be revised between rounds (e.g. a CI gate).
