#!/usr/bin/env bash
# install.sh — install the grill-me-kimi skill family into your Claude Code skills dir.
#
# Re-syncs the engine from bin/ into each skill folder, then copies the skills into
# ~/.claude/skills/ (override with CLAUDE_SKILLS_DIR). Idempotent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

echo "Installing grill-me-kimi family into: $SKILLS_DIR"

# Single source of truth for the engine: bin/kimi-review.sh -> each skill folder.
for d in "$REPO_DIR"/skills/*/; do
  cp "$REPO_DIR/bin/kimi-review.sh" "$d/kimi-review.sh"
  chmod +x "$d/kimi-review.sh"
done

mkdir -p "$SKILLS_DIR"
cp -R "$REPO_DIR"/skills/* "$SKILLS_DIR"/
chmod +x "$SKILLS_DIR"/*/kimi-review.sh 2>/dev/null || true

echo "Installed:"
for d in "$REPO_DIR"/skills/*/; do echo "  - $(basename "$d")"; done

# Prerequisite check (warn, don't fail).
if ! command -v kimi >/dev/null 2>&1; then
  echo
  echo "WARNING: the 'kimi' CLI is not on your PATH. Install it:"
  echo "  brew install kimi-cli   # or see https://github.com/MoonshotAI/kimi-cli"
elif [ ! -f "$HOME/.kimi/credentials/kimi-code.json" ]; then
  echo
  echo "NOTE: kimi CLI found but you're not logged in. Run once:  kimi login"
fi

echo
echo "Done. In Claude Code: /grill-me-kimi, /grill-with-docs-kimi, or /kimi-review"
