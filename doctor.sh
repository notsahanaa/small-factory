#!/usr/bin/env bash
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
STATE_DIR="${HOME}/.claude/small-factory"
EXPECTED_SKILLS=(small-factory small-setup small-spec small-subissues small-build small-merge)
FAIL=0

echo "small-factory doctor"
echo "===================="
echo ""

# Symlink checks
for name in "${EXPECTED_SKILLS[@]}"; do
  target="$SKILLS_DIR/$name"
  if [ -L "$target" ] && [ -f "$target/SKILL.md" ]; then
    echo "✓ $target → $(readlink "$target")"
  elif [ -e "$target" ]; then
    echo "✗ $target exists but is not a valid symlink to a skill dir"
    FAIL=1
  else
    echo "✗ $target missing — run install.sh"
    FAIL=1
  fi
done

# State dir
echo ""
if [ -d "$STATE_DIR/projects" ]; then
  echo "✓ State dir: $STATE_DIR/projects"
else
  echo "✗ State dir missing: $STATE_DIR/projects — run install.sh"
  FAIL=1
fi

# Global principles (informational only)
if [ -f "$STATE_DIR/principles.md" ]; then
  echo "✓ Global principles: $STATE_DIR/principles.md"
else
  echo "ℹ  No global principles set (optional)"
fi

# Linear MCP
echo ""
if [ -f "$HOME/.claude.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '.mcpServers | with_entries(select(.key | test("linear"; "i"))) | length > 0' "$HOME/.claude.json" >/dev/null 2>&1; then
    echo "✓ Linear MCP configured"
  else
    echo "✗ Linear MCP not found in ~/.claude.json"
    FAIL=1
  fi
else
  echo "ℹ  Cannot auto-check Linear MCP (no ~/.claude.json or no jq)"
fi

# Per-project config validity
echo ""
if [ -d "$STATE_DIR/projects" ]; then
  PROJECT_COUNT=0
  for proj in "$STATE_DIR"/projects/*/; do
    [ -d "$proj" ] || continue
    PROJECT_COUNT=$((PROJECT_COUNT + 1))
    slug=$(basename "$proj")
    if [ -f "$proj/config.yml" ]; then
      if grep -qE '^(project|commands|branches):' "$proj/config.yml"; then
        echo "✓ Project config: $slug"
      else
        echo "✗ Project config malformed: $slug (missing expected keys)"
        FAIL=1
      fi
    else
      echo "✗ Project dir without config.yml: $slug"
      FAIL=1
    fi
  done
  [ "$PROJECT_COUNT" -eq 0 ] && echo "ℹ  No projects configured yet — run /small-factory in a repo to start"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  VERSION=$(cat "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/VERSION" 2>/dev/null || echo "?")
  echo "✓ All checks passed. Running small-factory v$VERSION."
  exit 0
else
  echo "✗ One or more checks failed. See above."
  exit 1
fi
