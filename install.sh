#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILLS_DIR="${HOME}/.claude/skills"
STATE_DIR="${HOME}/.claude/small-factory"

# 1. Verify claude CLI exists
if ! command -v claude >/dev/null 2>&1; then
  echo "✗ claude CLI not found. Install Claude Code first: https://claude.com/code"
  exit 1
fi

# 2. Create dirs
mkdir -p "$SKILLS_DIR"
mkdir -p "$STATE_DIR/projects"

# 3. Symlink each skill (idempotent — overwrite existing symlinks)
for skill_dir in "$REPO_DIR"/skills/*/; do
  name=$(basename "$skill_dir")
  ln -sfn "$skill_dir" "$SKILLS_DIR/$name"
  echo "✓ Installed: $SKILLS_DIR/$name"
done

# 4. Linear MCP check (best-effort)
if [ -f "$HOME/.claude.json" ] && command -v jq >/dev/null 2>&1; then
  if ! jq -e '.mcpServers | with_entries(select(.key | test("linear"; "i"))) | length > 0' "$HOME/.claude.json" >/dev/null 2>&1; then
    echo ""
    echo "⚠  Linear MCP not detected in ~/.claude.json"
    echo "   small-factory relies on Linear for issue tracking. Set it up:"
    echo "   https://linear.app/changelog/2024-11-claude-mcp"
  fi
else
  echo ""
  echo "ℹ  Could not auto-check Linear MCP (no ~/.claude.json or no jq installed)."
  echo "   Ensure Linear MCP is configured before running /small-factory."
fi

# 5. Init principles prompt
PRINCIPLES_FILE="$STATE_DIR/principles.md"
if [ ! -f "$PRINCIPLES_FILE" ]; then
  cat <<'EOF'

────────────────────────────────────────────────────────────────────
Global principles (optional)
────────────────────────────────────────────────────────────────────

Global principles are guardrails the small-factory skills inject into
every spec, every build agent prompt, and every merge decision. They
apply across all your projects unless you override them per-project
later (per-project principles live at
~/.claude/small-factory/projects/<slug>/principles.md).

Examples:
  - Tests required for new behavior; bug fixes start with a failing test.
  - Prefer composition over inheritance.
  - No new external dependencies without a one-line justification.
  - Comments only when the WHY is non-obvious.
  - Always check error returns; never log-and-continue silently.
  - Avoid defensive checks for impossible states.

You can write yours now, skip and add later, or copy a starter template.
────────────────────────────────────────────────────────────────────
EOF
  read -rp "Set global principles now? [y/N/template]: " ans
  case "$ans" in
    y|Y)
      "${EDITOR:-vi}" "$PRINCIPLES_FILE"
      ;;
    t|T|template)
      cat > "$PRINCIPLES_FILE" <<'EOF'
# Global principles

- Tests required for new behavior; bug fixes start with a failing test.
- Prefer composition over inheritance.
- No new external dependencies without a one-line justification.
- Comments only when the WHY is non-obvious.

(Edit this file any time. Per-project overrides live at
~/.claude/small-factory/projects/<slug>/principles.md.)
EOF
      echo "✓ Starter template written to $PRINCIPLES_FILE — edit any time."
      ;;
    *)
      echo "ℹ  Skipped. The Setup skill will offer this again on your first project."
      ;;
  esac
fi

VERSION=$(cat "$REPO_DIR/VERSION")
echo ""
echo "✓ small-factory v$VERSION installed."
echo "  Run /small-factory in any Claude Code session inside a git repo to begin."
