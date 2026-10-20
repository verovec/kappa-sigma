#!/usr/bin/env bash
# Builds the SwiftPM package and assembles <pkg>/.build/AstroStack.app (debug, ad-hoc signed).
# Works with the Command Line Tools alone or with Xcode: shaders compile at runtime until E19
# (design §4.7), so no Xcode project and no .metallib are needed. Extra args go to `swift build`.
# Usage: scripts/app-bundle.sh apps/macos [swift build args]
set -euo pipefail
pkg="${1:?package dir}"; shift || true
cd "$pkg"
swift build --product AstroStackApp "$@"
bin="$(swift build --show-bin-path "$@")"

app=".build/AstroStack.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/AstroStackApp" "$app/Contents/MacOS/AstroStack"
cp App/Info.plist "$app/Contents/Info.plist"
# SwiftPM resource bundles (dependencies' privacy manifests today, kit resources later).
find "$bin" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$app/Contents/Resources/" \;
codesign --force --sign - --timestamp=none "$app" >/dev/null
echo "built $pkg/$app"
