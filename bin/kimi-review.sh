#!/usr/bin/env bash
# kimi-review.sh — one adversarial review round from a second model.
#
# Part of the grill-me-kimi skill family. Runs a read-only second pair of eyes on a
# written plan (or code diff) and prints its review to stdout. There is no built-in
# default model: you configure the reviewer via env vars (see "Reviewer
# configuration" below and docs/PROVIDERS.md). Kimi is one documented option among
# several, not a hardcoded dependency.
#
# Round 1 starts a fresh review. Rounds >= 2 ask the reviewer to resume the same
# conversation (when KIMI_REVIEW_CMD supports it, e.g. the `kimi` CLI's --continue)
# so it remembers the concerns it raised and checks whether the revised plan
# addresses them. The engine itself is stateless between rounds; a reviewer that
# has no session memory just re-reviews from scratch every round, which still works
# but repeats itself.
#
# Exit codes: 0 ok | 2 bad args | 5 no plan file | 6 reviewer failed/empty output
#             7 no reviewer configured | 124 timeout
set -uo pipefail

PLAN_FILE="PLAN.md"
REPO_DIR="$(pwd)"
ROUND=1
MAX_ROUNDS="${MAX_ROUNDS:-3}"
TIMEOUT_SECS="${KIMI_REVIEW_TIMEOUT:-420}"
MODE="plan"            # plan = review an implementation plan | code = review a diff

usage() {
  cat >&2 <<'EOF'
Usage: kimi-review.sh [--mode plan|code] [--plan-file PATH] [--repo DIR] [--round N] [--max-rounds N] [--timeout SECS]

  --mode plan|code   plan: review an implementation plan (default).
                     code: review a code diff (the file is a unified diff).
  --plan-file PATH   File to review: a plan (plan mode) or a diff (code mode).
                     Alias: --diff-file. Default: PLAN.md
  --repo DIR         Working directory the reviewer reads for context (default: current dir)
  --round N          Review round (default: 1). N>=2 asks for the same session.
  --max-rounds N     Cap, for the prompt only — enforcement is the caller's job
                     (see bin/kimi-loop.sh). Default: 3, or env MAX_ROUNDS.
  --timeout SECS     Kill the call after this many seconds (default: 420)

Reviewer configuration (exactly one, checked in this order):
  KIMI_REVIEW_CMD                                    a command to run; reads the
                                                       prompt from $GRILL_REVIEW_PROMPT_FILE,
                                                       prints the review to stdout.
  KIMI_REVIEW_BASE_URL / _MODEL / _API_KEY            generic OpenAI-compatible
                                                       Chat Completions endpoint,
                                                       called in-process.
  (neither set)                                       aborts with exit 7.
See docs/PROVIDERS.md ("Which second model") for recipes, including Kimi.

Other env overrides:
  KIMI_REVIEW_TIMEOUT   Same as --timeout
  MAX_ROUNDS            Same as --max-rounds (default cap)
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

This is review round $ROUND of at most $MAX_ROUNDS. Earlier you reviewed a previous
version of $PLAN_FILE. The author has revised it to address your concerns. Re-read
$PLAN_FILE now.

For EVERY concern you raised in a previous round, state one of:
  ADDRESSED — and why you're satisfied
  PARTIALLY — what still falls short
  NOT ADDRESSED — what is missing
Then raise any NEW concern the revision introduced. Keep the same severity
prefixes and end with the single VERDICT line."
  fi
else
  # code mode: embed the diff so repo scoping can never hide it; the full files
  # live in the repo (the reviewer's working directory) for context.
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

This is review round $ROUND of at most $MAX_ROUNDS. Earlier you reviewed an earlier
version of this change. It has been revised. Re-read the new diff below and the
affected files.

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

# --- Reviewer resolution -------------------------------------------------------
PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/kimi-review-prompt.XXXXXX")"
trap 'rm -f "$PROMPT_FILE"' EXIT
printf '%s' "$PROMPT" > "$PROMPT_FILE"

export GRILL_REVIEW_PROMPT_FILE="$PROMPT_FILE"
export GRILL_REVIEW_ROUND="$ROUND"
export GRILL_REVIEW_MAX_ROUNDS="$MAX_ROUNDS"
export GRILL_REVIEW_MODE="$MODE"
export GRILL_REVIEW_PLAN_FILE="$PLAN_FILE"
export GRILL_REVIEW_REPO_DIR="$REPO_DIR"

TIMER=""
if command -v timeout >/dev/null 2>&1; then TIMER="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMER="gtimeout"; fi

_run_timed() {  # run a command with the timeout wrapper; stdin closed
  if [ -n "$TIMER" ]; then "$TIMER" "$TIMEOUT_SECS" "$@" < /dev/null
  else "$@" < /dev/null; fi
}

if [ -n "${KIMI_REVIEW_CMD:-}" ]; then
  OUT="$(_run_timed bash -c "$KIMI_REVIEW_CMD")"; rc=$?
elif [ -n "${KIMI_REVIEW_BASE_URL:-}" ] && [ -n "${KIMI_REVIEW_MODEL:-}" ] && [ -n "${KIMI_REVIEW_API_KEY:-}" ]; then
  # Generic OpenAI-compatible Chat Completions call. python3 stdlib only (no new
  # dependency) — see docs/PROVIDERS.md for which providers speak this API.
  OUT="$(_run_timed env KIMI_REVIEW_API_KEY="$KIMI_REVIEW_API_KEY" python3 - \
           "$KIMI_REVIEW_BASE_URL" "$KIMI_REVIEW_MODEL" "$PROMPT_FILE" <<'PY'
import json, os, sys, urllib.request

base_url, model, prompt_file = sys.argv[1], sys.argv[2], sys.argv[3]
with open(prompt_file, "r", encoding="utf-8") as fh:
    prompt = fh.read()

req = urllib.request.Request(
    base_url.rstrip("/") + "/chat/completions",
    data=json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}]}).encode("utf-8"),
    headers={
        "Authorization": "Bearer " + os.environ["KIMI_REVIEW_API_KEY"],
        "Content-Type": "application/json",
    },
    method="POST",
)
with urllib.request.urlopen(req) as resp:
    data = json.load(resp)
sys.stdout.write(data["choices"][0]["message"]["content"])
PY
)"; rc=$?
else
  echo "ERROR: no reviewer configured. Set one of:" >&2
  echo "  KIMI_REVIEW_CMD                                   a command reading \$GRILL_REVIEW_PROMPT_FILE" >&2
  echo "  KIMI_REVIEW_BASE_URL, KIMI_REVIEW_MODEL, KIMI_REVIEW_API_KEY   a generic OpenAI-compatible endpoint" >&2
  echo "See docs/PROVIDERS.md (\"Which second model\")." >&2
  exit 7
fi

[ "$rc" -eq 124 ] && { echo "ERROR: review timed out after ${TIMEOUT_SECS}s (round $ROUND)." >&2; exit 124; }
if [ "$rc" -ne 0 ]; then
  echo "ERROR: reviewer command failed (exit $rc, round $ROUND):" >&2
  printf '%s\n' "$OUT" | tail -5 >&2
  exit 6
fi
if [ -z "${OUT//[[:space:]]/}" ]; then
  echo "ERROR: reviewer produced no output (round $ROUND)." >&2
  exit 6
fi

printf '%s\n' "$OUT"
