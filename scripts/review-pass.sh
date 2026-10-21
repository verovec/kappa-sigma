#!/usr/bin/env bash
# Records that /code-review passed on the PR's current head: the gate `merge-pr.sh` requires it.
# The marker names the head SHA, so any later push needs a new review pass before the merge.
# Usage: scripts/review-pass.sh <pr-number> "<review summary>"   (called by `just review-pass`)
set -euo pipefail
pr="${1:?pr number}"
summary="${2:?review summary (findings fixed / rejected and why)}"

head_sha="$(gh pr view "$pr" --json headRefOid --jq .headRefOid)"
gh pr comment "$pr" --body "code-review: passed ${head_sha}

${summary}" >/dev/null
echo "review-pass: PR #$pr marked reviewed at ${head_sha:0:7}"
