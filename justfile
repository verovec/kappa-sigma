# Task runner for Kappa-Sigma (AstroStack 2). Run `just` to see available recipes.
# Host-native by design: the app and its Swift packages build on macOS with the Command Line Tools
# or Xcode; there is no container (Siril, GraXpert, StarNet and Metal are host-only). Why each
# gate exists: docs/engineering/swift-quality-playbook.md §9.
set shell := ["bash", "-uc"]
set dotenv-load := true
set export := true

pkg := "apps/macos"
app := pkg + "/.build/AstroStack.app"
# Swift Testing search paths SwiftPM forgets on a CLT-only host; empty under Xcode.
swiftflags := `./scripts/swift-test-flags.sh`
# SwiftLint looks for sourcekitd in Xcode only; on a CLT-only host point it at the CLT.
_sourcekit := 'dev="$(xcode-select -p)"; [ ! -d "$dev/usr/lib/sourcekitdInProc.framework" ] || export TOOLCHAIN_DIR="$dev"'

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

# Build the Swift packages and assemble apps/macos/.build/AstroStack.app (debug, ad-hoc signed).
app-build:
    @./scripts/app-bundle.sh {{pkg}} {{swiftflags}}

# Build, then open the app (and the given `.astrostack` projects); returns when the app quits.
app-run *projects: app-build
    open -W -n -a "{{justfile_directory()}}/{{app}}" {{projects}}

# Run the whole Swift suite (live suites self-skip without host tools/fixtures). Args pass through.
# ATTACHMENTS_PATH (set by CI) collects Attachment.record() outputs such as diff images.
test *args:
    cd {{pkg}} && swift test {{swiftflags}} --parallel ${ATTACHMENTS_PATH:+--attachments-path "$ATTACHMENTS_PATH"} {{args}}

# Fast loop: everything except the `Live…` suites.
test-unit *args:
    cd {{pkg}} && swift test {{swiftflags}} --parallel --skip Live {{args}}

# Only the `Live…` suites (host tools + ~/Documents/astro/fixtures), serial.
test-live *args:
    cd {{pkg}} && swift test {{swiftflags}} --no-parallel --filter Live ${ATTACHMENTS_PATH:+--attachments-path "$ATTACHMENTS_PATH"} {{args}}

# Coverage report (lcov + summary) under apps/macos/.build/coverage.
coverage:
    ./scripts/coverage.sh {{pkg}} {{swiftflags}}

# Format check + swift-format lint rules + SwiftLint metrics/house rules. Read-only; fails on issues.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v swiftlint >/dev/null || { echo "swiftlint missing: just setup"; exit 1; }
    {{_sourcekit}}
    cd {{pkg}}
    swift format lint --strict --recursive --parallel Sources Tests
    swiftlint lint --strict --quiet

# Auto-format the codebase in place (swift-format), then SwiftLint autocorrect.
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    {{_sourcekit}}
    cd {{pkg}}
    swift format format --in-place --recursive --parallel Sources Tests
    command -v swiftlint >/dev/null && swiftlint lint --fix --quiet || true

# Repo hygiene gate: Swift only, no pixels, no data symlinks, no large blobs, planning stays local.
hygiene:
    @./scripts/hygiene.sh

# Public API of the kits vs origin/main (run once a kit exposes `public` API — card 0049).
api-check *targets:
    cd {{pkg}} && git fetch -q origin main && swift package diagnose-api-breaking-changes origin/main {{targets}}

# Dead-code scan (Periphery, optional, local only).
deadcode:
    @command -v periphery >/dev/null || { echo "periphery missing (optional): brew install peripheryapp/periphery/periphery"; exit 0; }
    cd {{pkg}} && periphery scan --retain-public --quiet

# Benchmarks with local (tight) thresholds — package-benchmark, once a Benchmarks target exists.
bench *args:
    cd {{pkg}} && swift package --disable-sandbox benchmark {{args}}

# Merge a PR into main — the only sanctioned way: refuses unless every CI check is green.
merge pr:
    @./scripts/merge-pr.sh {{pr}}

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
