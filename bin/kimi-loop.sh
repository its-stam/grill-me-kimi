#!/usr/bin/env bash
# kimi-loop.sh — drives the full Act 2 review loop.
#
# Calls kimi-review.sh once per round, appends each round to a log file under a
# "## Round N — <reviewer>" heading, and stops at the first VERDICT: APPROVED or
# at the round cap (default 3, override with MAX_ROUNDS or --max-rounds). Before
# round 1 it hashes the file under review; if that hash changes after any round,
# the reviewer wrote to a file it was told to only read, and the loop aborts —
# this is the read-only proof, not a promise in a prompt.
#
# This script is the reference implementation of the loop contract (round
# bookkeeping, cap, escalation, read-only check) and what the test suite drives.
# The skills in skills/*/SKILL.md mostly call kimi-review.sh round-by-round
# themselves instead, because a real Act 2 run needs an editor (Claude) reading
# each round's concerns and revising the plan in between — a plain loop like this
# one has no such editor and just re-submits the same file every round. Use it
# directly when you don't need that: e.g. a CI gate that reviews a frozen plan or
# diff and wants a single pass/fail exit code.
#
# Exit codes: 0 approved | 2 bad args | 5 no plan/diff file | 6 reviewer error
#             7 no reviewer configured | 8 read-only violation | 9 capped, no approval
#             124 timeout
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_SH="$SELF_DIR/kimi-review.sh"

PLAN_FILE="PLAN.md"
LOG_FILE="PLAN-REVIEW-LOG.md"
REPO_DIR="$(pwd)"
MODE="plan"
MAX_ROUNDS="${MAX_ROUNDS:-3}"
TIMEOUT_SECS="${KIMI_REVIEW_TIMEOUT:-420}"

usage() {
  cat >&2 <<'EOF'
Usage: kimi-loop.sh [--mode plan|code] [--plan-file PATH] [--log-file PATH] [--repo DIR] [--max-rounds N] [--timeout SECS]

Runs the review loop end to end: rounds 1..MAX_ROUNDS, each appended to
--log-file under "## Round N — Kimi", stopping at the first VERDICT: APPROVED or
the round cap. Before round 1 the file under review is hashed; any change to it
after a round aborts the loop (read-only proof).

Env:
  MAX_ROUNDS           Default cap (default: 3). --max-rounds overrides it.
  KIMI_REVIEW_TIMEOUT  Per-round timeout in seconds (default: 420)
  Reviewer config: KIMI_REVIEW_CMD, or KIMI_REVIEW_BASE_URL/_MODEL/_API_KEY.
  See docs/PROVIDERS.md.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)       MODE="${2:?}"; shift 2 ;;
    --plan-file|--diff-file) PLAN_FILE="${2:?}"; shift 2 ;;
    --log-file)   LOG_FILE="${2:?}"; shift 2 ;;
    --repo)       REPO_DIR="${2:?}"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="${2:?}"; shift 2 ;;
    --timeout)    TIMEOUT_SECS="${2:?}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[ -f "$PLAN_FILE" ] || { echo "ERROR: input file not found: $PLAN_FILE" >&2; exit 5; }
[ -x "$REVIEW_SH" ] || { echo "ERROR: engine not found or not executable: $REVIEW_SH" >&2; exit 5; }

_hash() { shasum -a 256 "$PLAN_FILE" 2>/dev/null | awk '{print $1}'; }
BASELINE_HASH="$(_hash)"

: > "$LOG_FILE"   # one run, one log; callers that want cross-run history append themselves
OPEN_CONCERNS=""
ROUND=1

while [ "$ROUND" -le "$MAX_ROUNDS" ]; do
  OUT="$("$REVIEW_SH" --mode "$MODE" --plan-file "$PLAN_FILE" --repo "$REPO_DIR" \
                       --round "$ROUND" --max-rounds "$MAX_ROUNDS" --timeout "$TIMEOUT_SECS")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: round $ROUND failed (exit $rc):" >&2
    printf '%s\n' "$OUT" | tail -5 >&2
    exit "$rc"
  fi

  NOW_HASH="$(_hash)"
  if [ "$NOW_HASH" != "$BASELINE_HASH" ]; then
    echo "ERROR: read-only violation — $PLAN_FILE changed during round $ROUND. The reviewer" >&2
    echo "  is only allowed to read it. Baseline: $BASELINE_HASH  Now: $NOW_HASH" >&2
    exit 8
  fi

  {
    echo "## Round $ROUND — Kimi"
    echo
    printf '%s\n' "$OUT"
    echo
  } >> "$LOG_FILE"

  OPEN_CONCERNS="$(printf '%s\n' "$OUT" | grep -E '\[(BLOCKER|MAJOR)\]' || true)"
  VERDICT_LINE="$(printf '%s\n' "$OUT" | grep -E '^VERDICT:' | tail -1)"

  case "$VERDICT_LINE" in
    *APPROVED*) echo "APPROVED after round $ROUND. See $LOG_FILE."; exit 0 ;;
  esac

  ROUND=$((ROUND + 1))
done

echo "ERROR: not approved after $MAX_ROUNDS round(s). Escalating to the human. Open concerns:" >&2
if [ -n "$OPEN_CONCERNS" ]; then
  printf '%s\n' "$OPEN_CONCERNS" >&2
else
  echo "  (no BLOCKER/MAJOR line in the final round's output; see $LOG_FILE)" >&2
fi
exit 9
