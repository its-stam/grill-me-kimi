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

usage() {
  cat >&2 <<'EOF'
Usage: kimi-review.sh [--plan-file PATH] [--repo DIR] [--round N] [--max-rounds N] [--timeout SECS]

  --plan-file PATH   Plan to review (default: PLAN.md)
  --repo DIR         Working directory Kimi reads (default: current dir)
  --round N          Review round (default: 1). N>=2 resumes the same session.
  --max-rounds N     Cap, for the prompt only (default: 5)
  --timeout SECS     Kill the call after this many seconds (default: 420)

Env overrides:
  KIMI_MODEL         Pin a model (default: your OAuth plan's default)
  KIMI_NO_THINKING=1 Disable thinking mode (default: thinking on)
  KIMI_REVIEW_TIMEOUT  Same as --timeout
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --plan-file) PLAN_FILE="${2:?}"; shift 2 ;;
    --repo)      REPO_DIR="${2:?}"; shift 2 ;;
    --round)     ROUND="${2:?}"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="${2:?}"; shift 2 ;;
    --timeout)   TIMEOUT_SECS="${2:?}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# --- Preflight ---------------------------------------------------------------
command -v kimi >/dev/null 2>&1 || {
  echo "ERROR: kimi CLI not found. Install it:  brew install kimi-cli" >&2; exit 3; }

[ -f "$HOME/.kimi/credentials/kimi-code.json" ] || {
  echo "ERROR: not logged in to Kimi. Run once:  kimi login" >&2; exit 4; }

[ -f "$PLAN_FILE" ] || {
  echo "ERROR: plan file not found: $PLAN_FILE" >&2; exit 5; }

# --- Review prompt -----------------------------------------------------------
# Read-only adversarial reviewer. Substance over nitpicks. Hard output contract:
# numbered concerns with severity, then exactly one VERDICT line.
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

# --- Build argv --------------------------------------------------------------
# --quiet     = --print --output-format text --final-message-only (clean stdout)
# --plan      = plan mode, no file mutations (read-only reviewer)
# --work-dir  = scope Kimi to the repo
# Built incrementally so it stays safe under `set -u` on bash 3.2 (macOS), where
# expanding an empty array errors with "unbound variable".
# Model: env override > config default_model > kimi-k2.6 fallback. The Kimi OAuth
# config often ships no default model, so relying on it gives "LLM not set".
RESOLVED_MODEL="${KIMI_MODEL:-}"
if [ -z "$RESOLVED_MODEL" ]; then
  RESOLVED_MODEL="$(grep -E '^[[:space:]]*default_model' "$HOME/.kimi/config.toml" 2>/dev/null | head -1 | cut -d'"' -f2)"
fi
[ -z "$RESOLVED_MODEL" ] && RESOLVED_MODEL="kimi-k2.6"

KIMI_CMD=(kimi --quiet --plan --work-dir "$REPO_DIR")
[ "$ROUND" -ge 2 ] && KIMI_CMD+=(--continue)             # resume the same session
KIMI_CMD+=(-m "$RESOLVED_MODEL")
[ -z "${KIMI_NO_THINKING:-}" ] && KIMI_CMD+=(--thinking) # deeper review by default
KIMI_CMD+=(--prompt "$PROMPT")

# --- Portable timeout --------------------------------------------------------
TIMER=""
if command -v timeout >/dev/null 2>&1; then TIMER="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMER="gtimeout"; fi

if [ -n "$TIMER" ]; then
  OUT="$("$TIMER" "$TIMEOUT_SECS" "${KIMI_CMD[@]}" < /dev/null)"; rc=$?
else
  OUT="$("${KIMI_CMD[@]}" < /dev/null)"; rc=$?
fi

if [ "$rc" -eq 124 ]; then
  echo "ERROR: Kimi review timed out after ${TIMEOUT_SECS}s (round $ROUND)." >&2
  exit 124
fi

# Kimi exits 0 even with no usable model (expired OAuth, or no model configured),
# printing only "LLM not set". Catch that and the empty-output case so the caller
# never mistakes a setup failure for a real review.
if [ -z "${OUT//[[:space:]]/}" ] || printf '%s' "$OUT" | grep -q "LLM not set"; then
  echo "ERROR: Kimi produced no review (\"LLM not set\" / empty output)." >&2
  echo "  Most likely your OAuth login expired. Re-login:  kimi login" >&2
  echo "  Or pin a model your plan supports:  KIMI_MODEL=kimi-k2.6 ./kimi-review.sh ..." >&2
  exit 6
fi

printf '%s\n' "$OUT"
exit "$rc"
