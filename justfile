# Task runner for Kappa-Sigma (AstroStack 2). Run `just` to see available recipes.
# Host-native by design: the app and its Swift packages build on macOS with Xcode; there is no
# container (Siril, GraXpert, StarNet and Metal are host-only). Card 0040 fills the app recipes.
set shell := ["bash", "-uc"]
set dotenv-load := true
set export := true

pkg := "apps/macos"

# List all recipes.
default:
    @just --list

# Build the Swift packages and the app (debug).
app-build:
    @test -f {{pkg}}/Package.swift && (cd {{pkg}} && swift build) || echo "no Swift package yet — card 0040"

# Run the app from the debug build.
app-run:
    @test -f {{pkg}}/Package.swift && (cd {{pkg}} && swift run AstroStackApp) || echo "no Swift package yet — card 0040"

# Run the Swift test suite. Extra args pass through: `just test --filter ImageKit`.
test *args:
    @test -f {{pkg}}/Package.swift && (cd {{pkg}} && swift test {{args}}) || echo "no Swift package yet — card 0040"

# Lint + format-check (read-only; fails on issues).
lint:
    @test -f {{pkg}}/Package.swift && (cd {{pkg}} && swift-format lint --recursive --strict Sources Tests) || echo "no Swift package yet — card 0040"

# Auto-format the codebase in place.
fmt:
    @test -f {{pkg}}/Package.swift && (cd {{pkg}} && swift-format format --in-place --recursive Sources Tests) || true

# The pre-push gate: lint + test.
check: lint test

# Exactly what CI runs.
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
