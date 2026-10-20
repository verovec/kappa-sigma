#!/usr/bin/env bash
# Test continuity gate (testing-conventions.md §5: a test modification is a breaking change).
# Compares BASE..HEAD and fails when the PR weakens the suite without saying so:
#   - a test file under apps/macos/Tests was deleted, or lost lines (an existing test changed);
#   - the number of tests (`@Test` + `func test`) went down.
# Either is allowed only when the PR body carries a line starting with `Test-change:` that
# explains why (CI passes the body through PR_BODY). Adding tests never needs anything.
# Usage: scripts/test-ratchet.sh <base-ref> <head-ref>
set -euo pipefail
base="${1:?base ref}"; head="${2:?head ref}"
tests_dir="apps/macos/Tests"
cd "$(git rev-parse --show-toplevel)"

count_tests() { # <ref> → number of test functions at that ref
  { git grep -c -E '@Test\b|func test[A-Z_]' "$1" -- "$tests_dir" 2>/dev/null || true; } \
    | awk -F: '{ s += $NF } END { print s + 0 }'
}

before="$(count_tests "$base")"
after="$(count_tests "$head")"
deleted="$(git diff --name-only --diff-filter=D "$base" "$head" -- "$tests_dir" | grep -E '\.swift$' || true)"
weakened="$(git diff --numstat --diff-filter=M "$base" "$head" -- "$tests_dir" \
  | awk '$2 > 0 && $3 ~ /\.swift$/ { print $3 " (-" $2 " lines)" }' || true)"

echo "test-ratchet: $before → $after test functions ($base..$head)"
[ -z "$deleted" ]  || printf 'test-ratchet: deleted test files:\n%s\n' "$deleted"
[ -z "$weakened" ] || printf 'test-ratchet: existing test files with removed lines:\n%s\n' "$weakened"

justified=0
if printf '%s\n' "${PR_BODY:-}" | grep -qE '^\s*Test-change:\s*\S'; then justified=1; fi

fail=0
if [ "$after" -lt "$before" ] && [ "$justified" -eq 0 ]; then
  echo "test-ratchet: FAILED — test count decreased without a 'Test-change:' justification in the PR body"; fail=1
fi
if { [ -n "$deleted" ] || [ -n "$weakened" ]; } && [ "$justified" -eq 0 ]; then
  echo "test-ratchet: FAILED — existing tests changed or removed without a 'Test-change:' justification in the PR body"; fail=1
fi
[ "$fail" -eq 0 ] || exit 1
[ "$justified" -eq 0 ] || echo "test-ratchet: change justified in the PR body (Test-change:)"
echo "test-ratchet: ok"
