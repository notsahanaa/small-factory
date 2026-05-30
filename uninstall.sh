#!/usr/bin/env bash
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
STATE_DIR="${HOME}/.claude/small-factory"
PURGE=0

[ "${1:-}" = "--purge" ] && PURGE=1

for name in small-factory small-setup small-spec small-subissues small-build small-merge; do
  target="$SKILLS_DIR/$name"
  if [ -L "$target" ]; then
    rm "$target"
    echo "✓ Removed: $target"
  fi
done

if [ "$PURGE" -eq 1 ]; then
  if [ -d "$STATE_DIR" ]; then
    rm -rf "$STATE_DIR"
    echo "✓ Removed user state: $STATE_DIR"
  fi
  echo ""
  echo "✓ Fully uninstalled (--purge): symlinks AND user state removed."
else
  echo ""
  echo "✓ Symlinks removed. User state at $STATE_DIR preserved (configs, principles, project history)."
  echo "  Re-run install.sh any time to re-link."
  echo "  Use --purge to also remove user state."
fi
