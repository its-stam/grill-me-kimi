#!/usr/bin/env bash
# install.sh — install the grill-me-kimi skill family into your Claude Code skills dir.
#
# Copies the skills into ~/.claude/skills/ (override with CLAUDE_SKILLS_DIR). In this
# repo, skills/*/kimi-review.sh is a symlink to bin/kimi-review.sh — the single
# source of truth, so the repo copies can never drift from each other. A symlink
# doesn't survive being copied onto a machine that doesn't have bin/ alongside it,
# so this script materializes a real file (and bin/kimi-loop.sh, if present) at
# each installed skill. Idempotent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

echo "Installing grill-me-kimi family into: $SKILLS_DIR"

mkdir -p "$SKILLS_DIR"
cp -R "$REPO_DIR"/skills/* "$SKILLS_DIR"/

for d in "$SKILLS_DIR"/*/; do
  [ -e "$d/kimi-review.sh" ] || [ -L "$d/kimi-review.sh" ] || continue
  rm -f "$d/kimi-review.sh"   # may be a symlink copied verbatim from the repo checkout
  cp "$REPO_DIR/bin/kimi-review.sh" "$d/kimi-review.sh"
  chmod +x "$d/kimi-review.sh"
  if [ -f "$REPO_DIR/bin/kimi-loop.sh" ]; then
    cp "$REPO_DIR/bin/kimi-loop.sh" "$d/kimi-loop.sh"
    chmod +x "$d/kimi-loop.sh"
  fi
done

echo "Installed:"
for d in "$REPO_DIR"/skills/*/; do echo "  - $(basename "$d")"; done

# Prerequisite check (warn, don't fail) — only relevant if you wire up the kimi
# CLI as your reviewer (KIMI_REVIEW_CMD); this repo has no default provider.
if command -v kimi >/dev/null 2>&1; then
  if [ ! -f "$HOME/.kimi-code/credentials/kimi-code.json" ] && [ ! -f "$HOME/.kimi/credentials/kimi-code.json" ]; then
    echo
    echo "NOTE: kimi CLI found but you're not logged in. Run once:  kimi login"
  fi
fi

echo
echo "No reviewer is configured by default — set KIMI_REVIEW_CMD or"
echo "KIMI_REVIEW_BASE_URL/_MODEL/_API_KEY before running a review. See docs/PROVIDERS.md."
echo
echo "Done. In Claude Code: /grill-me-kimi, /grill-with-docs-kimi, or /kimi-review"
