# Using a different model or provider

Act 2 runs through the **Kimi Code CLI** (`kimi`), but `kimi` is really a generic
agent harness: it can drive many model providers, not just Kimi. So you can keep the
exact same review loop (read-only `--plan` mode, `--continue` session memory, the
`VERDICT:` contract) while swapping the *brain* for DeepSeek, Qwen, a local Ollama
model, the Moonshot API, Claude, or Gemini.

**For any OpenAI-compatible model, no code change is needed.** You add a provider +
model to your kimi config and select it with `KIMI_MODEL`. The engine
(`bin/kimi-review.sh`) copies your config through untouched (it only strips one
incompatible capability flag), so a model you configure there is available to the
skill.

> Secrets rule: an API key for one of these providers is a secret. Put it in an
> **environment variable** or in your kimi config **in your home directory**
> (`~/.kimi-code/config.toml`) — never in this repo. Nothing in this repo contains a
> key, and it should stay that way.

---

## How model selection works

kimi reads two tables from its config (`~/.kimi-code/config.toml`, or `~/.kimi/config.toml`):

```toml
[providers.<provider-name>]
type = "openai_legacy"            # see the type table below
base_url = "https://api.example.com/v1"
api_key = ""                       # leave empty and pass via env, or set here (home dir only)

[models.<model-alias>]
provider = "<provider-name>"
model = "<the provider's model id>"
max_context_size = 131072
```

Then pick that model alias:

```bash
KIMI_MODEL=<model-alias> ~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round 1
```

`KIMI_MODEL` overrides the config's `default_model` for that one run. Leave it unset
to use whatever `default_model` is (Kimi's `kimi-for-coding` on the OAuth plan).

### Provider `type` values (from kimi-cli)

| `type` | Use for |
|---|---|
| `kimi` | Kimi native (OAuth subscription or Moonshot API key) |
| `openai_legacy` | Any OpenAI-compatible Chat Completions API — DeepSeek, Qwen/DashScope, Ollama, Moonshot, OpenRouter, vLLM |
| `openai_responses` | OpenAI Responses API |
| `anthropic` | Claude |
| `google_genai` / `gemini` | Gemini |
| `vertexai` | Gemini on Vertex AI |

`openai_legacy` also reads a `reasoning_key` (default `reasoning_content`) — which is
exactly the field DeepSeek's reasoner returns, so reasoning models work out of the box.

---

## Recipes

Model IDs change over time — confirm the current ones in each provider's docs. The
endpoints and the shape are what matter.

### DeepSeek

```toml
[providers.deepseek]
type = "openai_legacy"
base_url = "https://api.deepseek.com/v1"
api_key = ""                       # or export OPENAI_API_KEY / DEEPSEEK_API_KEY

[models.deepseek-reasoner]
provider = "deepseek"
model = "deepseek-reasoner"        # or "deepseek-chat"
max_context_size = 65536
```
```bash
OPENAI_API_KEY="$DEEPSEEK_API_KEY" KIMI_MODEL=deepseek-reasoner \
  ~/.claude/skills/kimi-review/kimi-review.sh --plan-file PLAN.md --round 1
```

### Qwen (Alibaba DashScope, OpenAI-compatible)

```toml
[providers.qwen]
type = "openai_legacy"
base_url = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"   # .cn for China
api_key = ""                       # or export OPENAI_API_KEY / DASHSCOPE_API_KEY

[models.qwen-max]
provider = "qwen"
model = "qwen-max"                 # or qwen-plus, qwen3-coder-plus, ...
max_context_size = 131072
```

### Local model via Ollama (free, offline)

```toml
[providers.ollama]
type = "openai_legacy"
base_url = "http://localhost:11434/v1"
api_key = "ollama"                 # any non-empty dummy

[models.local-qwen]
provider = "ollama"
model = "qwen2.5-coder:14b"        # whatever you've pulled
max_context_size = 32768
```

### Moonshot API (instead of the OAuth subscription)

If you'd rather use a Moonshot API key than the OAuth login:

```toml
[providers.moonshot]
type = "openai_legacy"
base_url = "https://api.moonshot.ai/v1"
api_key = ""                       # or export OPENAI_API_KEY / MOONSHOT_API_KEY

[models.kimi-k2]
provider = "moonshot"
model = "kimi-k2.6"
max_context_size = 262144
```

### Claude or Gemini as the reviewer

Possible (`type = "anthropic"` with `base_url = "https://api.anthropic.com"`, or
`type = "gemini"`), but note the whole point of Act 2 is a *different* provider than
the one that wrote the plan. If Claude wrote the plan, reviewing with Claude is the
echo chamber this skill exists to avoid. Prefer a non-Claude reviewer.

---

## Swapping the harness entirely

If you want to drop `kimi` and drive a completely different CLI (e.g. `codex`, or a
raw `curl` to an API), there is exactly **one** place to change: the `KIMI_CMD`
assembly near the end of `bin/kimi-review.sh`. It builds the argv that runs the
review and prints the result to stdout. Keep two contracts and the skills keep working:

1. The command reads `PLAN.md` and the repo **read-only** and prints its review to stdout.
2. The review ends with a single line: `VERDICT: APPROVED` or `VERDICT: CHANGES_REQUESTED`.

Re-run `./install.sh` after editing so the installed copies under
`~/.claude/skills/*/` pick up your change.
