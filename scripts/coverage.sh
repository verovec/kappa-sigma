#!/usr/bin/env bash
# Line coverage for the SwiftPM package: runs the suite with instrumentation, exports lcov and a
# per-file summary. Usage: scripts/coverage.sh apps/macos [extra swift test args]
# Floor: when `.coverage-floor` exists next to Package.swift, the run fails below that figure
# (whole percent). It is fixed at 95% by the PO (24/10, pick-card §7): a card never moves it.
set -euo pipefail
pkg="${1:?package dir}"; shift || true
cd "$pkg"
swift test --parallel --enable-code-coverage "$@"
bin="$(swift build --show-bin-path)"
# The CLT's SwiftPM builds one PackageTests.xctest; Xcode's (Swift Build) one bundle per test
# target: llvm-cov reads them all, the first positional, the others as -object.
bundles=()
while IFS= read -r bundle; do bundles+=("$bundle"); done < <(
  find "$bin" -maxdepth 1 -name '*PackageTests.xctest' | head -1)
if [ ${#bundles[@]} -eq 0 ]; then
  while IFS= read -r bundle; do bundles+=("$bundle"); done < <(
    find "$bin" -maxdepth 1 -name '*Tests.xctest' | sort)
fi
[ ${#bundles[@]} -gt 0 ] || { echo "no test bundle (*Tests.xctest) under $bin"; exit 1; }
objects=()
for bundle in "${bundles[@]}"; do
  exe="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
  if [ ${#objects[@]} -eq 0 ]; then objects+=("$exe"); else objects+=(-object "$exe"); fi
done
prof="$bin/codecov/default.profdata"
mkdir -p .build/coverage
xcrun llvm-cov export -format=lcov "${objects[@]}" -instr-profile "$prof" -ignore-filename-regex='Tests|\.build' > .build/coverage/lcov.info
xcrun llvm-cov report "${objects[@]}" -instr-profile "$prof" -ignore-filename-regex='Tests|\.build' | tee .build/coverage/summary.txt
total="$(awk '/^TOTAL/ { print $(NF-3) }' .build/coverage/summary.txt)"
echo "$total" > .build/coverage/lines.txt
echo "line coverage: $total"
if [ -f .coverage-floor ]; then
  floor="$(tr -d ' %\n' < .coverage-floor)"
  pct="${total%\%}"
  if awk -v p="$pct" -v f="$floor" 'BEGIN { exit !(p + 0 < f + 0) }'; then
    echo "coverage: FAILED — $total is below the floor ${floor}% (.coverage-floor)"; exit 1
  fi
  echo "coverage: above the floor ${floor}%"
fi
