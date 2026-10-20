# Task runner for Kappa-Sigma (AstroStack 2). Run `just` to see available recipes.
# Host-native by design: the app and its Swift packages build on macOS with Xcode; there is no
# container (Siril, GraXpert, StarNet and Metal are host-only). Card 0040 creates Package.swift;
# every Swift recipe below guards on it until then. Why each gate exists:
# docs/engineering/swift-quality-playbook.md §9.
set shell := ["bash", "-uc"]
set dotenv-load := true
set export := true

pkg := "apps/macos"
_guard := "test -f " + pkg + "/Package.swift || { echo 'no Swift package yet — card 0040'; exit 0; }"

# List all recipes.
default:
    @just --list

# First-run setup: quality tools + git hooks. Safe to re-run.
setup:
    brew list swiftlint >/dev/null 2>&1 || brew install swiftlint
    just hooks
    just doctor

# Check the host: toolchain, Metal Toolchain, swiftlint, Siril/GraXpert/StarNet, data folders.
doctor:
    @./scripts/doctor.sh

# Install the pre-push hook (runs `just check`).
hooks:
    @ln -sf "$(pwd)/scripts/git-hooks/pre-push" "$(git rev-parse --git-path hooks)/pre-push" && echo "pre-push hook installed"

# Build the Swift packages and the app (debug).
app-build:
    @{{_guard}}; cd {{pkg}} && swift build

# Run the app from the debug build.
app-run:
    @{{_guard}}; cd {{pkg}} && swift run AstroStackApp

# Run the whole Swift suite (live suites self-skip without host tools/fixtures). Args pass through.
# ATTACHMENTS_PATH (set by CI) collects Attachment.record() outputs such as diff images.
test *args:
    @{{_guard}}; cd {{pkg}} && swift test --parallel ${ATTACHMENTS_PATH:+--attachments-path "$ATTACHMENTS_PATH"} {{args}}

# Fast loop: everything except the `Live…` suites.
test-unit *args:
    @{{_guard}}; cd {{pkg}} && swift test --parallel --skip Live {{args}}

# Only the `Live…` suites (host tools + ~/Documents/astro/fixtures), serial.
test-live *args:
    @{{_guard}}; cd {{pkg}} && swift test --no-parallel --filter Live ${ATTACHMENTS_PATH:+--attachments-path "$ATTACHMENTS_PATH"} {{args}}

# Coverage report (lcov + summary) under apps/macos/.build/coverage.
coverage:
    @{{_guard}}; ./scripts/coverage.sh {{pkg}}

# Format check + swift-format lint rules + SwiftLint metrics/house rules. Read-only; fails on issues.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    {{_guard}}
    command -v swiftlint >/dev/null || { echo "swiftlint missing: just setup"; exit 1; }
    cd {{pkg}}
    swift format lint --strict --recursive --parallel Sources Tests
    swiftlint lint --strict --quiet

# Auto-format the codebase in place (swift-format), then SwiftLint autocorrect.
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    {{_guard}}
    cd {{pkg}}
    swift format format --in-place --recursive --parallel Sources Tests
    command -v swiftlint >/dev/null && swiftlint lint --fix --quiet || true

# Repo hygiene gate: Swift only, no pixels, no data symlinks, no large blobs, planning stays local.
hygiene:
    @./scripts/hygiene.sh

# Public API of the kits vs origin/main (run once a kit exposes `public` API — card 0049).
api-check *targets:
    @{{_guard}}; cd {{pkg}} && git fetch -q origin main && swift package diagnose-api-breaking-changes origin/main {{targets}}

# Dead-code scan (Periphery, optional, local only).
deadcode:
    @{{_guard}}; command -v periphery >/dev/null || { echo "periphery missing (optional): brew install peripheryapp/periphery/periphery"; exit 0; }
    @{{_guard}}; cd {{pkg}} && periphery scan --retain-public --quiet

# Benchmarks with local (tight) thresholds — package-benchmark, once a Benchmarks target exists.
bench *args:
    @{{_guard}}; cd {{pkg}} && swift package --disable-sandbox benchmark {{args}}

# The pre-push gate: hygiene + lint + build + full suite including live tests.
check: hygiene lint app-build test

# Exactly what CI runs (live suites self-skip on the runner).
ci: check

# Download the offline Gaia catalogues Siril needs for SPCC into ~/Documents/astro/library/catalogues.
download-catalogues:
    ASTRO_LIBRARY_DIR="$HOME/Documents/astro/library" ./scripts/download-catalogues.sh

# Refresh the gitnexus code-graph (incremental).
gitnexus-sync:
    @.claude/hooks/gitnexus-sync.sh

# Force a full gitnexus re-index.
gitnexus-reindex:
    @.claude/hooks/gitnexus-sync.sh --force
