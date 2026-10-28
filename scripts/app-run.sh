#!/usr/bin/env bash
# Open the built AstroStack.app (and the given .astrostack projects), replacing the instance
# that may still run: it is asked to quit — never killed — and waited for, so every project.db
# is checkpointed and every owner marker removed before the new bundle starts (card 0147).
# With one instance allowed (LSMultipleInstancesProhibited), `open` would only bring a running
# app forward: the script fails instead of pretending the new build runs. It never quits an
# AstroStack of another bundle (the installed copy stacking a night, say): only this one.
# Usage: scripts/app-run.sh <path/to/AstroStack.app> [project.astrostack ...]
set -euo pipefail

app="$1"
shift
bundle_id="fr.astrostack.AstroStack"

# The running app, as LaunchServices lists it (no AppleScript, no Automation prompt).
running_asn() { lsappinfo find "bundleid=$bundle_id" 2>/dev/null | head -1; }

asn="$(running_asn)"
if [[ -n "$asn" ]]; then
  running_path="$(lsappinfo info "$asn" 2>/dev/null | sed -n 's/^ *bundle path="\(.*\)"$/\1/p')"
  app_path="$(cd "$app" 2>/dev/null && pwd -P || echo "$app")"
  if [[ -n "$running_path" && "$running_path" != "$app_path" ]]; then
    echo "app-run: another AstroStack is running ($running_path) — quit it yourself first" >&2
    exit 1
  fi
  # Ask, do not wait for the reply (a Save sheet would hold it two minutes): the loop judges.
  osascript -e 'ignoring application responses' \
    -e "tell application id \"$bundle_id\" to quit" -e 'end ignoring' >/dev/null 2>&1 || true
  # Documents close and checkpoint on quit; give them up to 30 s.
  for _ in $(seq 1 300); do
    [[ -z "$(running_asn)" ]] && break
    sleep 0.1
  done
  if [[ -n "$(running_asn)" ]]; then
    echo "app-run: AstroStack is still running (a quit cancelled?) — not opening the new build" >&2
    exit 1
  fi
fi

open -W -a "$app" "$@"
