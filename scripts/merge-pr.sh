#!/usr/bin/env bash
# The only way a PR lands on main: refuses unless every CI check exists and reports success.
# GitHub cannot enforce this here (private repo, no branch protection), so the tool does.
# Usage: scripts/merge-pr.sh <pr-number>   (called by `just merge <n>`)
set -euo pipefail
pr="${1:?pr number}"
# Every job of .github/workflows/tests.yml must be present and green — a missing job (workflow
# edited, run cancelled, still queued) is a failure, not a pass.
required=("test continuity" "hygiene · lint · build · test")

state="$(gh pr view "$pr" --json state,isDraft,mergeable,baseRefName --jq '"\(.state) \(.isDraft) \(.mergeable) \(.baseRefName)"')"
read -r st draft mergeable base <<<"$state"
[ "$st" = "OPEN" ]        || { echo "merge-pr: PR #$pr is $st, not open"; exit 1; }
[ "$draft" = "false" ]    || { echo "merge-pr: PR #$pr is a draft"; exit 1; }
[ "$base" = "main" ]      || { echo "merge-pr: PR #$pr targets $base, not main"; exit 1; }
[ "$mergeable" != "CONFLICTING" ] || { echo "merge-pr: PR #$pr has conflicts with main"; exit 1; }

# Wait for in-flight checks (the watch exits 0 even on failure, so the verdict comes after).
gh pr checks "$pr" --watch --interval 15 >/dev/null 2>&1 || true
checks="$(gh pr checks "$pr" --json name,state --jq '.[] | "\(.state)\t\(.name)"')"

fail=0
for name in "${required[@]}"; do
  line="$(printf '%s\n' "$checks" | awk -F'\t' -v n="$name" '$2 == n' | tail -1)"
  if [ -z "$line" ]; then echo "merge-pr: ✗ check missing: $name"; fail=1; continue; fi
  s="${line%%	*}"
  if [ "$s" = "SUCCESS" ]; then echo "merge-pr: ✓ $name"; else echo "merge-pr: ✗ $name → $s"; fail=1; fi
done
# Any other check that exists must not be red either.
while IFS=$'\t' read -r s name; do
  [ -n "$name" ] || continue
  case " ${required[*]} " in *" $name "*) continue ;; esac
  case "$s" in SUCCESS|SKIPPED|NEUTRAL) ;; *) echo "merge-pr: ✗ extra check $name → $s"; fail=1 ;; esac
done <<<"$checks"
[ "$fail" -eq 0 ] || { echo "merge-pr: REFUSED — fix the branch, never bypass"; exit 1; }

# The head must still be what the checks ran on.
head_sha="$(gh pr view "$pr" --json headRefOid --jq .headRefOid)"
run_sha="$(gh pr checks "$pr" --json name,link --jq '.[0].link' | sed -E 's#.*/runs/([0-9]+)/.*#\1#' | xargs -I{} gh run view {} --json headSha --jq .headSha 2>/dev/null || true)"
if [ -n "$run_sha" ] && [ "$run_sha" != "$head_sha" ]; then
  echo "merge-pr: REFUSED — checks ran on $run_sha but the PR head is $head_sha"; exit 1
fi

gh pr merge "$pr" --squash --delete-branch
echo "merge-pr: PR #$pr merged into main"
