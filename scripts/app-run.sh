#!/usr/bin/env bash
# Open the built AstroStack.app (and the given .astrostack projects), replacing the instance
# that may still run: it is asked to quit — never killed — and waited for, so every project.db
# is checkpointed and every owner marker removed before the new bundle starts (card 0147).
# With one instance allowed (LSMultipleInstancesProhibited), `open` would only bring a running
# app forward: the script fails instead of pretending the new build runs.
# Usage: scripts/app-run.sh <path/to/AstroStack.app> [project.astrostack ...]
set -euo pipefail

app="$1"
shift

# By bundle id through LaunchServices: the app this user runs, whatever its path; a process-list
# regex on the path would match a debugger or an editor holding it, or miss a path with
# metacharacters.
running() { osascript -e 'application id "fr.astrostack.AstroStack" is running' 2>/dev/null | grep -q true; }

if running; then
  # By bundle id: the running app, not whatever LaunchServices would resolve by name.
  # A quit the user cancels makes osascript fail: the loop below judges, not `set -e`.
  osascript -e 'tell application id "fr.astrostack.AstroStack" to quit' >/dev/null 2>&1 || true
  # Documents close and checkpoint on quit; give them up to 30 s.
  for _ in $(seq 1 300); do
    running || break
    sleep 0.1
  done
  if running; then
    echo "app-run: AstroStack is still running (a quit cancelled?) — not opening the new build" >&2
    exit 1
  fi
fi

open -W -a "$app" "$@"
