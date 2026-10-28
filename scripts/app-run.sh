#!/usr/bin/env bash
# Open the built AstroStack.app (and the given .astrostack projects), replacing the instance
# that may still run: it is asked to quit — never killed — and waited for, so every project.db
# is checkpointed and every owner marker removed before the new bundle starts (card 0147).
# Usage: scripts/app-run.sh <path/to/AstroStack.app> [project.astrostack ...]
set -euo pipefail

app="$1"
shift

if osascript -e 'application "AstroStack" is running' 2>/dev/null | grep -q true; then
  osascript -e 'tell application "AstroStack" to quit' >/dev/null
  # Documents close and checkpoint on quit; give them up to 30 s.
  for _ in $(seq 1 300); do
    if ! osascript -e 'application "AstroStack" is running' 2>/dev/null | grep -q true; then break; fi
    sleep 0.1
  done
fi

open -W -a "$app" "$@"
