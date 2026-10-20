#!/usr/bin/env bash
# Host readiness for the E10–E19 work: toolchain, quality tools, host tools (invoked, never
# bundled), data folders. Advisory: prints one line per item, exits 1 only when something
# REQUIRED for `just check` is missing. Live tests self-skip on the optional items.
set -uo pipefail

missing=0
ok()   { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ○ %s\n' "$1"; }
bad()  { printf '  ✗ %s\n' "$1"; missing=1; }

echo "toolchain"
if swift --version >/dev/null 2>&1; then ok "swift $(swift --version 2>&1 | head -1 | sed -E 's/.*Swift version ([0-9.]+).*/\1/')"; else bad "swift (install Xcode or the Command Line Tools)"; fi
if swift format --version >/dev/null 2>&1; then ok "swift format $(swift format --version 2>&1)"; else bad "swift format (bundled with the Swift 6 toolchain)"; fi
if xcodebuild -version >/dev/null 2>&1; then
  ok "$(xcodebuild -version | tr '\n' ' ')"
  if xcrun -sdk macosx metal --version >/dev/null 2>&1; then ok "Metal Toolchain (precompiled .metallib path available)"
  else warn "Metal Toolchain missing: xcodebuild -downloadComponent metalToolchain (runtime shader compile until then)"; fi
else
  warn "Xcode not selected (Command Line Tools only): shaders compile at runtime, no Instruments, no signing"
fi

echo "quality tools"
command -v just >/dev/null 2>&1 && ok "just $(just --version | awk '{print $2}')" || bad "just (brew install just)"
command -v swiftlint >/dev/null 2>&1 && ok "swiftlint $(swiftlint version)" || bad "swiftlint (brew install swiftlint) — required by just lint"
command -v periphery >/dev/null 2>&1 && ok "periphery $(periphery version 2>/dev/null)" || warn "periphery (optional, dead-code scan: brew install peripheryapp/periphery/periphery)"

echo "host tools (invoked, never bundled — a missing one greys its process in the app)"
# The app resolves the bundles directly (design §4.4); PATH is a convenience, not a requirement.
siril="/Applications/Siril.app/Contents/MacOS/siril-cli"
if [ -x "$siril" ]; then ok "siril-cli $(defaults read /Applications/Siril.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null) → $siril"
elif command -v siril-cli >/dev/null 2>&1; then ok "siril-cli → $(command -v siril-cli)"
else warn "Siril 1.4.x not found (/Applications/Siril.app or siril-cli on PATH): Siril live tests skip"; fi
graxpert="$(ls -d /Applications/GraXpert*.app 2>/dev/null | head -1)"
if [ -n "$graxpert" ]; then ok "GraXpert $(defaults read "$graxpert/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null) → $graxpert"
elif command -v graxpert >/dev/null 2>&1; then ok "graxpert → $(command -v graxpert)"
else warn "GraXpert not found: background/denoise live tests skip"; fi
if command -v starnet2 >/dev/null 2>&1; then ok "starnet2 → $(command -v starnet2)"; else warn "starnet2 not on PATH: star-layer live tests skip (user install, never bundled)"; fi

echo "data (read-only, outside every repo)"
root="$HOME/Documents/astro"
for d in captures runs library fixtures; do
  [ -d "$root/$d" ] && ok "$root/$d" || warn "$root/$d absent (live tests skip)"
done
[ -d "$HOME/AstroStack/Projects" ] && ok "$HOME/AstroStack/Projects" || warn "$HOME/AstroStack/Projects not created yet (the app creates it)"

echo "git hooks"
hook="$(git rev-parse --git-path hooks)/pre-push"
[ -x "$hook" ] && ok "pre-push hook installed" || warn "pre-push hook not installed: just hooks"

exit "$missing"
