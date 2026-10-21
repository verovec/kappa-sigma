#!/usr/bin/env bash
# The only way a PR lands on main: refuses unless every CI check exists and reports success AND
# a /code-review pass is recorded on the current head (`just review-pass`).
# GitHub cannot enforce this here (private repo, no branch protection), so the tool does.
# Usage: scripts/merge-pr.sh <pr-number>   (called by `just merge <n>`)
set -euo pipefail
pr="${1:?pr number}"
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "merge-pr: '$pr' is not a PR number"; exit 1; }
# Every job of .github/workflows/tests.yml must be present and green — a missing job (workflow
# edited, run cancelled, still queued) is a failure, not a pass.
required=("test continuity" "hygiene · lint · build · test")
# Resolved once from the checkout's remote: every gh call then names that same repo, and the
# merge itself never switches the local checkout (it fails from a worktree).
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

state="$(gh pr view "$pr" --repo "$repo" --json state,isDraft,mergeable,baseRefName,author --jq '"\(.state) \(.isDraft) \(.mergeable) \(.baseRefName) \(.author.login)"')"
read -r st draft mergeable base author <<<"$state"
[ "$st" = "OPEN" ]        || { echo "merge-pr: PR #$pr is $st, not open"; exit 1; }
[ "$draft" = "false" ]    || { echo "merge-pr: PR #$pr is a draft"; exit 1; }
[ "$base" = "main" ]      || { echo "merge-pr: PR #$pr targets $base, not main"; exit 1; }
[ "$mergeable" != "CONFLICTING" ] || { echo "merge-pr: PR #$pr has conflicts with main"; exit 1; }

# Wait for in-flight checks (the watch exits 0 even on failure, so the verdict comes after).
gh pr checks "$pr" --repo "$repo" --watch --interval 15 >/dev/null 2>&1 || true
checks="$(gh pr checks "$pr" --repo "$repo" --json name,state --jq '.[] | "\(.state)\t\(.name)"')"

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
head_sha="$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)"
run_sha="$(gh pr checks "$pr" --repo "$repo" --json name,link --jq '.[0].link' | sed -E 's#.*/runs/([0-9]+)/.*#\1#' | xargs -I{} gh run view {} --repo "$repo" --json headSha --jq .headSha 2>/dev/null || true)"
if [ -n "$run_sha" ] && [ "$run_sha" != "$head_sha" ]; then
  echo "merge-pr: REFUSED — checks ran on $run_sha but the PR head is $head_sha"; exit 1
fi

# The code review must have passed on this exact head: the first line of a comment by the PR's
# author (a quoted marker or another account does not count), read across every comment page.
markers="$(gh api --paginate "repos/$repo/issues/$pr/comments" \
  --jq '.[] | [.user.login, (.body | split("\n")[0] | rtrimstr("\r"))] | @tsv' \
  | awk -F'\t' -v a="$author" '$1 == a { print $2 }')"
if ! grep -qFx "code-review: passed ${head_sha}" <<<"$markers"; then
  echo "merge-pr: REFUSED — no code review recorded on ${head_sha:0:7}: run /code-review, then"
  echo "          just review-pass $pr \"<summary>\""
  exit 1
fi
echo "merge-pr: ✓ code review on ${head_sha:0:7}"

# --match-head-commit: GitHub refuses if a push landed after the checks and the review above.
gh pr merge "$pr" --repo "$repo" --squash --delete-branch --match-head-commit "$head_sha"
echo "merge-pr: PR #$pr merged into main"
