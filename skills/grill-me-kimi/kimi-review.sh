#!/usr/bin/env bash
# kimi-review.sh — one adversarial review round via the Kimi Code CLI.
#
# Part of the grill-me-kimi skill family. Runs Kimi as a read-only second pair
# of eyes on a written plan and prints its review to stdout. Auth is the CLI's
# concern: if you ran `kimi login` (OAuth), that account is used — no API key,
# no per-token billing.
#
# Round 1 starts a fresh review. Rounds >= 2 pass --continue so the SAME Kimi
# session in this working directory remembers the concerns it raised and checks
# whether the revised plan addresses them.
#
# Exit codes: 0 ok | 2 bad args | 3 no kimi | 4 not logged in | 5 no plan file
#             124 timeout | other = kimi's own failure
set -uo pipefail

PLAN_FILE="PLAN.md"
REPO_DIR="$(pwd)"
ROUND=1
MAX_ROUNDS=5
TIMEOUT_SECS="${KIMI_REVIEW_TIMEOUT:-420}"
MODE="plan"            # plan = review an implementation plan | code = review a diff

usage() {
  cat >&2 <<'EOF'
Usage: kimi-review.sh [--mode plan|code] [--plan-file PATH] [--repo DIR] [--round N] [--max-rounds N] [--timeout SECS]

  --mode plan|code   plan: review an implementation plan (default).
                     code: review a code diff (the file is a unified diff).
  --plan-file PATH   File to review: a plan (plan mode) or a diff (code mode).
                     Alias: --diff-file. Default: PLAN.md
  --repo DIR         Working directory Kimi reads for context (default: current dir)
  --round N          Review round (default: 1). N>=2 resumes the same session.
  --max-rounds N     Cap, for the prompt only (default: 5)
  --timeout SECS     Kill the call after this many seconds (default: 420)

Env overrides:
  KIMI_MODEL         Pin a model (default: the config's default_model)
  KIMI_NO_THINKING=1 Disable thinking mode (default: thinking on)
  KIMI_REVIEW_TIMEOUT  Same as --timeout
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)      MODE="${2:?}"; shift 2 ;;
    --plan-file|--diff-file) PLAN_FILE="${2:?}"; shift 2 ;;
    --repo)      REPO_DIR="${2:?}"; shift 2 ;;
    --round)     ROUND="${2:?}"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="${2:?}"; shift 2 ;;
    --timeout)   TIMEOUT_SECS="${2:?}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "$MODE" in plan|code) ;; *) echo "ERROR: --mode must be plan or code" >&2; exit 2 ;; esac

# --- Preflight ---------------------------------------------------------------
command -v kimi >/dev/null 2>&1 || {
  echo "ERROR: kimi CLI not found. Install it:  brew install kimi-cli" >&2; exit 3; }

# Resolve the Kimi data dir. A migrated "Kimi Code" install keeps its config and
# OAuth credentials in ~/.kimi-code; a plain install uses ~/.kimi. Honor an
# explicit KIMI_SHARE_DIR, else prefer ~/.kimi-code when present.
SHARE="${KIMI_SHARE_DIR:-}"
if [ -z "$SHARE" ]; then
  if [ -f "$HOME/.kimi-code/config.toml" ]; then SHARE="$HOME/.kimi-code"
  else SHARE="$HOME/.kimi"; fi
fi

[ -f "$SHARE/credentials/kimi-code.json" ] || {
  echo "ERROR: not logged in to Kimi ($SHARE). Run once:  kimi login" >&2; exit 4; }

[ -f "$PLAN_FILE" ] || {
  echo "ERROR: input file not found: $PLAN_FILE" >&2; exit 5; }

# --- Review prompt -----------------------------------------------------------
# Read-only adversarial reviewer. Substance over nitpicks. Hard output contract:
# numbered findings with severity, then exactly one VERDICT line.
if [ "$MODE" = "plan" ]; then
  read -r -d '' RULES <<'EOF' || true
You are a senior software architect doing an ADVERSARIAL, read-only review of an
implementation plan BEFORE any code is written. You are NOT the author. Assume the
plan is flawed and find the flaws. This is read-only: do NOT modify, create, or
delete any file. Only read the plan and the surrounding codebase.

Judge on substance, not style:
- Correctness: will this actually solve the stated problem?
- Edge cases and failure modes the plan ignores (errors, empty/huge inputs,
  concurrency, partial failure, retries, idempotency).
- Hidden complexity, and simpler alternatives that get 90% of the value.
- Unstated assumptions, and places the plan contradicts the real codebase
  (cite the file/path when it does).
- Security, data loss, and irreversibility where relevant.

Output format, exactly:
1. A numbered list of concerns. Prefix each with a severity:
   [BLOCKER] must fix or the plan fails, [MAJOR] likely to bite, [MINOR] worth noting.
   Be concrete and reference the relevant plan section or code path.
2. Then a single final line, nothing after it:
   VERDICT: APPROVED        (only if there are no BLOCKER or MAJOR concerns left)
   VERDICT: CHANGES_REQUESTED
EOF

  if [ "$ROUND" -le 1 ]; then
    PROMPT="$RULES

Review the plan at: $PLAN_FILE
Read it in full, then read the parts of the codebase it touches before judging."
  else
    PROMPT="$RULES

This is review round $ROUND of at most $MAX_ROUNDS. Earlier in THIS session you
reviewed a previous version of $PLAN_FILE. The author has revised it to address
your concerns. Re-read $PLAN_FILE now.

For EVERY concern you raised in a previous round, state one of:
  ADDRESSED — and why you're satisfied
  PARTIALLY — what still falls short
  NOT ADDRESSED — what is missing
Then raise any NEW concern the revision introduced. Keep the same severity
prefixes and end with the single VERDICT line."
  fi
else
  # code mode: embed the diff so work-dir scoping can never hide it; the full files
  # live in the repo (Kimi's work dir) and it reads them for context.
  DIFF_CONTENT="$(cat "$PLAN_FILE")"
  read -r -d '' RULES <<'EOF' || true
You are a senior engineer doing an ADVERSARIAL, read-only review of a CODE CHANGE
before it merges. You are NOT the author. Assume there are bugs and find them. This
is read-only: do NOT modify, create, or delete any file. The unified diff under
review is given below; the full files are in your working directory — read them for
context before judging.

Judge on substance, not style:
- Correctness bugs: off-by-one, wrong conditions, null/nil, type/encoding, async/await.
- Unhandled edge cases and error paths (empty/huge input, failures, timeouts, retries).
- Security: injection, authz/authn gaps, unsafe input, secrets, path traversal, SSRF.
- Concurrency: races, deadlocks, non-atomic read-modify-write.
- Resource leaks, unbounded growth, N+1 queries.
- Breaking changes to public APIs/contracts; missing migrations.
- Behavior changed with no matching test.
- A simpler or safer way to get the same result.

Read whatever files you need first, then produce the COMPLETE review as your final
answer — written out in full, not a summary, and not a reference to earlier messages.

Output format, exactly:
1. A numbered list of findings. Prefix each with a severity:
   [BLOCKER] must fix before merge, [MAJOR] likely to bite, [MINOR] worth noting.
   Reference the file and line or hunk for each.
2. Then a single final line, nothing after it:
   VERDICT: APPROVED        (only if there are no BLOCKER or MAJOR findings left)
   VERDICT: CHANGES_REQUESTED
EOF

  if [ "$ROUND" -le 1 ]; then
    PROMPT="$RULES

DIFF UNDER REVIEW:
$DIFF_CONTENT"
  else
    PROMPT="$RULES

This is review round $ROUND of at most $MAX_ROUNDS. Earlier in THIS session you
reviewed an earlier version of this change. It has been revised. Re-read the new
diff below and the affected files.

For EVERY finding you raised in a previous round, state one of:
  ADDRESSED — and why you're satisfied
  PARTIALLY — what still falls short
  NOT ADDRESSED — what is missing
Then raise any NEW finding the revision introduced. Keep the same severity prefixes
and end with the single VERDICT line.

REVISED DIFF UNDER REVIEW:
$DIFF_CONTENT"
  fi
fi

# --- Build argv --------------------------------------------------------------
# --quiet     = --print --output-format text --final-message-only (clean stdout)
# --plan      = plan mode, no file mutations (read-only reviewer)
# --work-dir  = scope Kimi to the repo
# Built incrementally so it stays safe under `set -u` on bash 3.2 (macOS), where
# expanding an empty array errors with "unbound variable".
# If the resolved config carries capability values this kimi build rejects (e.g.
# "tool_use" from a newer Kimi Code), feed a sanitized copy via --config-file while
# still reading OAuth creds from $SHARE. The model comes from the config's
# default_model; override only with KIMI_MODEL.
# Thinking mode: KIMI_NO_THINKING env wins, else the persisted toggle
# (~/.kimi-grill/thinking = "on"|"off"), else on. The review skills flip the file
# via an on/off picker; this is what they read back.
THINKING="on"
[ -f "$HOME/.kimi-grill/thinking" ] && case "$(tr -d '[:space:]' < "$HOME/.kimi-grill/thinking" 2>/dev/null)" in
  off|OFF|0|false) THINKING="off" ;;
esac
[ -n "${KIMI_NO_THINKING:-}" ] && THINKING="off"

ENV_PREFIX=()
CFG_ARG=()
if [ "$SHARE" != "$HOME/.kimi" ]; then
  ENV_PREFIX=(env "KIMI_SHARE_DIR=$SHARE")
fi
if [ -f "$SHARE/config.toml" ]; then
  SAN="$HOME/.kimi-grill/config.toml"
  mkdir -p "$HOME/.kimi-grill"
  sed -E 's/,[[:space:]]*"tool_use"//g; s/"tool_use",[[:space:]]*//g' "$SHARE/config.toml" > "$SAN"
  CFG_ARG=(--config-file "$SAN")
fi

# Built incrementally; length-guarded so empty arrays don't trip `set -u` on bash 3.2.
KIMI_CMD=()
[ ${#ENV_PREFIX[@]} -gt 0 ] && KIMI_CMD+=("${ENV_PREFIX[@]}")
KIMI_CMD+=(kimi --quiet --plan --work-dir "$REPO_DIR")
[ ${#CFG_ARG[@]} -gt 0 ] && KIMI_CMD+=("${CFG_ARG[@]}")
[ "$ROUND" -ge 2 ] && KIMI_CMD+=(--continue)             # resume the same session
[ -n "${KIMI_MODEL:-}" ] && KIMI_CMD+=(-m "$KIMI_MODEL") # else config default_model
[ "$THINKING" = "on" ] && KIMI_CMD+=(--thinking)        # env > ~/.kimi-grill/thinking > on
KIMI_CMD+=(--prompt "$PROMPT")

# --- Run helpers -------------------------------------------------------------
TIMER=""
if command -v timeout >/dev/null 2>&1; then TIMER="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMER="gtimeout"; fi

_run() {  # run a command array with the timeout wrapper; stdin closed
  if [ -n "$TIMER" ]; then "$TIMER" "$TIMEOUT_SECS" "$@" < /dev/null
  else "$@" < /dev/null; fi
}

# kimi exits 0 even when it produced no usable review (expired OAuth → "LLM not
# set", or an API error like a 401/429 quota message). Treat those as failures so
# the caller never mistakes a setup error for a real review.
_failed() {
  [ -z "${1//[[:space:]]/}" ] && return 0
  printf '%s' "$1" | grep -qE "LLM not set|Error code:|Invalid Authentication|exceeded_current_quota|insufficient balance" && return 0
  return 1
}

# --- Primary: OAuth path -----------------------------------------------------
OUT="$(_run "${KIMI_CMD[@]}")"; rc=$?
[ "$rc" -eq 124 ] && { echo "ERROR: Kimi review timed out after ${TIMEOUT_SECS}s (round $ROUND)." >&2; exit 124; }

if ! _failed "$OUT"; then
  printf '%s\n' "$OUT"
  exit 0
fi

# --- Fallback: API key (OAuth primary stays first) ---------------------------
# Only used when the OAuth path produced no review AND a key is available. Uses an
# OpenAI-compatible endpoint via env overrides (default: Moonshot API = same Kimi
# model family). Override base/model with GRILL_KIMI_BASE_URL / GRILL_KIMI_MODEL.
API_KEY="${GRILL_KIMI_API_KEY:-${MOONSHOT_API_KEY:-${KIMI_API_KEY:-}}}"
if [ -n "$API_KEY" ]; then
  echo "NOTE: OAuth path produced no review; trying API fallback..." >&2
  API_BASE="${GRILL_KIMI_BASE_URL:-https://api.moonshot.ai/v1}"
  API_MODEL="${GRILL_KIMI_MODEL:-kimi-k2.6}"
  API_STORE="$HOME/.kimi-grill/api-store"; mkdir -p "$API_STORE"

  API_CMD=(kimi --quiet --plan --work-dir "$REPO_DIR")
  [ "$ROUND" -ge 2 ] && API_CMD+=(--continue)              # session memory within API mode
  [ "$THINKING" = "on" ] && API_CMD+=(--thinking)
  API_CMD+=(--prompt "$PROMPT")

  # Key passed via the env of this call (not argv) so it never lands in `ps aux`.
  OUT2="$(KIMI_SHARE_DIR="$API_STORE" KIMI_API_KEY="$API_KEY" \
          KIMI_BASE_URL="$API_BASE" KIMI_MODEL_NAME="$API_MODEL" \
          _run "${API_CMD[@]}")"; rc2=$?
  [ "$rc2" -eq 124 ] && { echo "ERROR: API fallback timed out after ${TIMEOUT_SECS}s." >&2; exit 124; }

  if ! _failed "$OUT2"; then
    echo "NOTE: OAuth unavailable — used API fallback ($API_BASE, $API_MODEL)." >&2
    printf '%s\n' "$OUT2"
    exit 0
  fi

  echo "ERROR: both OAuth and the API fallback failed (round $ROUND)." >&2
  echo "  OAuth: expired? re-login with  kimi login  (creds dir: $SHARE)" >&2
  echo "  API ($API_BASE): $(printf '%s' "$OUT2" | tr '\n' ' ' | cut -c1-200)" >&2
  exit 6
fi

# --- No fallback available ---------------------------------------------------
echo "ERROR: Kimi produced no review (\"LLM not set\" / empty output)." >&2
echo "  Most likely your OAuth login expired. Re-login:  kimi login   (creds dir: $SHARE)" >&2
echo "  Or set an API key (MOONSHOT_API_KEY) for the fallback — see docs/PROVIDERS.md." >&2
exit 6
