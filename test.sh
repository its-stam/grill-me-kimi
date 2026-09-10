#!/usr/bin/env bash
# test.sh — grill-me-kimi test suite. No network, no real model, no git actions.
# Everything runs against tests/mock-reviewer.sh via KIMI_REVIEW_CMD.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_SH="$REPO_DIR/bin/kimi-review.sh"
LOOP_SH="$REPO_DIR/bin/kimi-loop.sh"
MOCK_SH="$REPO_DIR/tests/mock-reviewer.sh"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

assert_eq() {  # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
assert_contains() {  # desc haystack needle
  case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "expected to contain [$3], got:
$2" ;; esac
}
assert_not_contains() {  # desc haystack needle
  case "$2" in *"$3"*) bad "$1" "expected NOT to contain [$3], got:
$2" ;; *) ok "$1" ;; esac
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/grill-me-kimi-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- f. bash -n on every shell script -----------------------------------------
while IFS= read -r f; do
  if bash -n "$f" 2>/tmp/bashn.$$; then
    ok "bash -n: $f"
  else
    bad "bash -n: $f" "$(cat /tmp/bashn.$$)"
  fi
  rm -f /tmp/bashn.$$
done < <(find "$REPO_DIR" -name '*.sh' -not -path '*/.git/*' | sort)

# --- 5e. no provider configured -> exit 7, names the three variables ----------
(
  cd "$WORK"
  printf '# plan\nsome content\n' > PLAN.md
  unset KIMI_REVIEW_CMD KIMI_REVIEW_BASE_URL KIMI_REVIEW_MODEL KIMI_REVIEW_API_KEY 2>/dev/null
  "$REVIEW_SH" --plan-file PLAN.md --round 1 >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
RC="$(cat /tmp/rc.$$)"; ERR="$(cat /tmp/err.$$)"
assert_eq "no-provider: exit code is non-zero" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
assert_contains "no-provider: names KIMI_REVIEW_BASE_URL" "$ERR" "KIMI_REVIEW_BASE_URL"
assert_contains "no-provider: names KIMI_REVIEW_MODEL" "$ERR" "KIMI_REVIEW_MODEL"
assert_contains "no-provider: names KIMI_REVIEW_API_KEY" "$ERR" "KIMI_REVIEW_API_KEY"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- missing plan file -> exit 5 ----------------------------------------------
(
  cd "$WORK"
  rm -f NOPE.md
  KIMI_REVIEW_CMD="$MOCK_SH" "$REVIEW_SH" --plan-file NOPE.md --round 1 >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
assert_eq "missing plan file: exit 5" "5" "$(cat /tmp/rc.$$)"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- 5a. single round via KIMI_REVIEW_CMD mock --------------------------------
(
  cd "$WORK"
  printf '# plan\n' > PLAN.md
  KIMI_REVIEW_CMD="$MOCK_SH" "$REVIEW_SH" --plan-file PLAN.md --round 1 >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
assert_eq "round 1 via mock: exit 0" "0" "$(cat /tmp/rc.$$)"
assert_contains "round 1 via mock: CHANGES_REQUESTED" "$(cat /tmp/out.$$)" "VERDICT: CHANGES_REQUESTED"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

(
  cd "$WORK"
  KIMI_REVIEW_CMD="$MOCK_SH" "$REVIEW_SH" --plan-file PLAN.md --round 3 >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
assert_eq "round 3 via mock: exit 0" "0" "$(cat /tmp/rc.$$)"
assert_contains "round 3 via mock: APPROVED" "$(cat /tmp/out.$$)" "VERDICT: APPROVED"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- 5b. loop terminates after round 3 with approval --------------------------
(
  cd "$WORK"
  rm -f PLAN.md PLAN-REVIEW-LOG.md
  printf '# plan\nsome content\n' > PLAN.md
  KIMI_REVIEW_CMD="$MOCK_SH" "$LOOP_SH" --plan-file PLAN.md --log-file PLAN-REVIEW-LOG.md \
    >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
assert_eq "loop (approve on round 3): exit 0" "0" "$(cat /tmp/rc.$$)"
assert_eq "loop: PLAN.md exists" "1" "$([ -f "$WORK/PLAN.md" ] && echo 1 || echo 0)"
assert_eq "loop: PLAN-REVIEW-LOG.md exists" "1" "$([ -f "$WORK/PLAN-REVIEW-LOG.md" ] && echo 1 || echo 0)"
ROUND_HEADERS="$(grep -c '^## Round [0-9]* — Kimi' "$WORK/PLAN-REVIEW-LOG.md" 2>/dev/null || echo 0)"
assert_eq "loop: exactly 3 round headings in the log" "3" "$ROUND_HEADERS"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- 5c. mock that never approves -> capped, exit != 0, escalation list -------
(
  cd "$WORK"
  rm -f PLAN.md PLAN-REVIEW-LOG.md
  printf '# plan\nsome content\n' > PLAN.md
  MOCK_REVIEWER_MODE=never-approve KIMI_REVIEW_CMD="$MOCK_SH" "$LOOP_SH" \
    --plan-file PLAN.md --log-file PLAN-REVIEW-LOG.md >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
RC="$(cat /tmp/rc.$$)"; ERR="$(cat /tmp/err.$$)"
assert_eq "loop capped: exit code is non-zero" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
assert_contains "loop capped: escalation mentions BLOCKER" "$ERR" "[BLOCKER]"
assert_contains "loop capped: escalation says human" "$ERR" "human"
ROUND_HEADERS="$(grep -c '^## Round [0-9]* — Kimi' "$WORK/PLAN-REVIEW-LOG.md" 2>/dev/null || echo 0)"
assert_eq "loop capped: default MAX_ROUNDS is 3 (3 rounds ran)" "3" "$ROUND_HEADERS"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- MAX_ROUNDS overridable via env -------------------------------------------
(
  cd "$WORK"
  rm -f PLAN.md PLAN-REVIEW-LOG.md
  printf '# plan\nsome content\n' > PLAN.md
  MAX_ROUNDS=1 MOCK_REVIEWER_MODE=never-approve KIMI_REVIEW_CMD="$MOCK_SH" "$LOOP_SH" \
    --plan-file PLAN.md --log-file PLAN-REVIEW-LOG.md >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
ROUND_HEADERS="$(grep -c '^## Round [0-9]* — Kimi' "$WORK/PLAN-REVIEW-LOG.md" 2>/dev/null || echo 0)"
assert_eq "MAX_ROUNDS=1 env override: exactly 1 round ran" "1" "$ROUND_HEADERS"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- 5d. read-only violation: mock mutates the plan file ----------------------
(
  cd "$WORK"
  rm -f PLAN.md PLAN-REVIEW-LOG.md
  printf '# plan\nsome content\n' > PLAN.md
  MOCK_REVIEWER_MODE=mutate-plan KIMI_REVIEW_CMD="$MOCK_SH" "$LOOP_SH" \
    --plan-file PLAN.md --log-file PLAN-REVIEW-LOG.md >/tmp/out.$$ 2>/tmp/err.$$
  echo "$?" > /tmp/rc.$$
)
RC="$(cat /tmp/rc.$$)"; ERR="$(cat /tmp/err.$$)"
assert_eq "read-only violation: exit code is non-zero" "1" "$([ "$RC" -ne 0 ] && echo 1 || echo 0)"
assert_contains "read-only violation: error names the cause" "$ERR" "read-only violation"
rm -f /tmp/out.$$ /tmp/err.$$ /tmp/rc.$$

# --- repo skill copies are symlinks to the single canonical engine ------------
for s in grill-me-kimi grill-with-docs-kimi kimi-code-review kimi-review; do
  LINK="$REPO_DIR/skills/$s/kimi-review.sh"
  TARGET="$(readlink "$LINK" 2>/dev/null || echo '')"
  case "$TARGET" in
    *bin/kimi-review.sh) ok "skills/$s/kimi-review.sh symlinks to bin/kimi-review.sh" ;;
    *) bad "skills/$s/kimi-review.sh symlinks to bin/kimi-review.sh" "got target [$TARGET]" ;;
  esac
done

# --- install.sh materializes a real, working file (not a dangling symlink) ---
(
  CLAUDE_SKILLS_DIR="$WORK/installed-skills" "$REPO_DIR/install.sh" >/tmp/out.$$ 2>&1
  echo "$?" > /tmp/rc.$$
)
assert_eq "install.sh: exits 0" "0" "$(cat /tmp/rc.$$)"
INSTALLED="$WORK/installed-skills/kimi-review/kimi-review.sh"
assert_eq "install.sh: installed engine is a regular file, not a symlink" "1" \
  "$([ -f "$INSTALLED" ] && [ ! -L "$INSTALLED" ] && echo 1 || echo 0)"
(
  cd "$WORK"
  printf '# plan\n' > PLAN.md
  KIMI_REVIEW_CMD="$MOCK_SH" "$INSTALLED" --plan-file PLAN.md --round 3 >/tmp/out2.$$ 2>/tmp/err2.$$
  echo "$?" > /tmp/rc2.$$
)
assert_eq "install.sh: installed engine actually runs" "0" "$(cat /tmp/rc2.$$)"
rm -f /tmp/out.$$ /tmp/rc.$$ /tmp/out2.$$ /tmp/err2.$$ /tmp/rc2.$$

echo
echo "TOTAL: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
