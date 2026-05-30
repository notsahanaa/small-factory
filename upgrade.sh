#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$REPO_DIR"

OLD_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
git pull --ff-only
NEW_VERSION=$(cat VERSION)

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  echo "✓ Already on v$NEW_VERSION."
else
  echo "✓ Upgraded: v$OLD_VERSION → v$NEW_VERSION"
  echo "  Symlinks point at the repo — next /small-factory invocation loads the new version."
fi
