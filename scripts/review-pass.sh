#!/usr/bin/env bash
# Records that /code-review passed on the PR's current head: the gate `merge-pr.sh` requires it.
# The marker names the head SHA, so any later push needs a new review pass before the merge.
# Run it from the branch that was reviewed: it refuses unless that commit is the PR's head.
# Usage: scripts/review-pass.sh <pr-number> "<review summary>"   (called by `just review-pass`)
set -euo pipefail
pr="${1:?pr number}"
summary="${2:?review summary (findings fixed / rejected and why)}"
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "review-pass: '$pr' is not a PR number"; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

state="$(gh pr view "$pr" --repo "$repo" --json state,baseRefName,headRefOid,author \
  --jq '"\(.state) \(.baseRefName) \(.headRefOid) \(.author.login)"')"
read -r st base head_sha author <<<"$state"
[ "$st" = "OPEN" ]   || { echo "review-pass: PR #$pr is $st, not open"; exit 1; }
[ "$base" = "main" ] || { echo "review-pass: PR #$pr targets $base, not main"; exit 1; }
# merge-pr only counts the PR author's markers: one posted from another account would never match.
me="$(gh api user --jq .login)"
[ "$me" = "$author" ] || { echo "review-pass: gh is logged in as $me, the PR author is $author"; exit 1; }

# What was reviewed is the local tree: it must be clean and pushed as the PR's head.
[ -z "$(git status --porcelain)" ] \
  || { echo "review-pass: uncommitted or untracked changes — commit, push, review again"; exit 1; }
local_sha="$(git rev-parse HEAD)"
[ "$local_sha" = "$head_sha" ] \
  || { echo "review-pass: local ${local_sha:0:7} is not the PR head ${head_sha:0:7} — push or pull"; exit 1; }

gh pr comment "$pr" --repo "$repo" --body "code-review: passed ${head_sha}

${summary}" >/dev/null
echo "review-pass: PR #$pr marked reviewed at ${head_sha:0:7}"
