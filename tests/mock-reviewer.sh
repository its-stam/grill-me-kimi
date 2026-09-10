#!/usr/bin/env bash
# tests/mock-reviewer.sh — stands in for a real second model in tests. Wired up
# via KIMI_REVIEW_CMD, so kimi-review.sh calls this instead of a live model.
#
# Reads the round number from $GRILL_REVIEW_ROUND (exported by the engine).
# Default script: rounds 1 and 2 raise a [BLOCKER] concern, round 3 approves.
#
# MOCK_REVIEWER_MODE overrides:
#   never-approve   every round raises a [BLOCKER] concern (cap/escalation test)
#   mutate-plan     appends a line to $GRILL_REVIEW_PLAN_FILE before answering,
#                   simulating a reviewer that isn't actually read-only
set -uo pipefail

ROUND="${GRILL_REVIEW_ROUND:-1}"
MODE="${MOCK_REVIEWER_MODE:-normal}"
PLAN_FILE="${GRILL_REVIEW_PLAN_FILE:-PLAN.md}"

if [ "$MODE" = "mutate-plan" ]; then
  printf '\nmock reviewer wrote this — should never happen\n' >> "$PLAN_FILE"
fi

if [ "$MODE" = "never-approve" ] || [ "$ROUND" -lt 3 ]; then
  cat <<EOF
1. [BLOCKER] round $ROUND: the plan does not say how retries are bounded.
VERDICT: CHANGES_REQUESTED
EOF
else
  cat <<EOF
1. [MINOR] round $ROUND: looks fine.
VERDICT: APPROVED
EOF
fi
