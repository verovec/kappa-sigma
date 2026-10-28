#!/usr/bin/env bash
# The developer directory every recipe builds with, printed for the justfile's DEVELOPER_DIR.
# The active one (`xcode-select -p`, or DEVELOPER_DIR when already set) unless it cannot build
# SwiftUI: Command Line Tools 27.0 (Swift 6.4, installed 2026-10-28) ship no SwiftUIMacros plugin,
# so every `@State` fails ("plugin for module 'SwiftUIMacros' not found"). Then an installed
# Xcode is used instead — its compiler is the same Swift — with no `sudo xcode-select`.
set -euo pipefail
dev="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
# None selected: the CLT's default place, never an empty DEVELOPER_DIR exported to every recipe.
[ -n "$dev" ] || dev=/Library/Developer/CommandLineTools
# Missing: still a path (`just --list`, `just doctor` must load); the build says what is missing.
[ -d "$dev" ] || echo "developer-dir: no developer tools at $dev (xcode-select --install)" >&2
case "$dev" in
  */CommandLineTools)
    if [ ! -e "$dev/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
      for xcode in /Applications/Xcode.app /Applications/Xcode-*.app; do
        candidate="$xcode/Contents/Developer"
        plugin="$candidate/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
        if [ -e "$plugin/libSwiftUIMacros.dylib" ]; then
          dev="$candidate"
          break
        fi
      done
    fi
    ;;
esac
printf '%s' "$dev"
