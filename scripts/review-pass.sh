#!/usr/bin/env bash
# Records that /code-review passed on the PR's current head: the gate `merge-pr.sh` requires it.
# The marker names the head SHA, so any later push needs a new review pass before the merge.
# Run it from the branch that was reviewed: it refuses unless that commit is the PR's head.
# Usage: scripts/review-pass.sh <pr-number> "<review summary>"   (called by `just review-pass`)
set -euo pipefail
pr="${1:?pr number}"
summary="${2:?review summary (findings fixed / rejected and why)}"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

state="$(gh pr view "$pr" --repo "$repo" --json state,baseRefName,headRefOid \
  --jq '"\(.state) \(.baseRefName) \(.headRefOid)"')"
read -r st base head_sha <<<"$state"
[ "$st" = "OPEN" ]   || { echo "review-pass: PR #$pr is $st, not open"; exit 1; }
[ "$base" = "main" ] || { echo "review-pass: PR #$pr targets $base, not main"; exit 1; }

# What was reviewed is the local tree: it must be clean and pushed as the PR's head.
[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || { echo "review-pass: uncommitted changes — commit, push, review again"; exit 1; }
local_sha="$(git rev-parse HEAD)"
[ "$local_sha" = "$head_sha" ] \
  || { echo "review-pass: local ${local_sha:0:7} is not the PR head ${head_sha:0:7} — push or pull"; exit 1; }

gh pr comment "$pr" --repo "$repo" --body "code-review: passed ${head_sha}

${summary}" >/dev/null
echo "review-pass: PR #$pr marked reviewed at ${head_sha:0:7}"
