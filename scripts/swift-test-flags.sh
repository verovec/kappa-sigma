#!/usr/bin/env bash
# Extra `swift build`/`swift test` flags for a Command Line Tools-only host (no Xcode).
# CLT 26.x ships Swift Testing as Testing.framework under Library/Developer/Frameworks, but SwiftPM
# passes that folder as -I (not -F) and does not add the runtime paths, so `import Testing` fails
# and the test bundle cannot load lib_TestingInterop.dylib. Verified 2026-10-20 with Swift 6.3.3.
# Prints nothing when the active developer directory is an Xcode (CI): its SwiftPM needs no help.
set -euo pipefail
dev="$("$(dirname "$0")/developer-dir.sh")"
case "$dev" in
  */CommandLineTools) ;;
  *) exit 0 ;;
esac
lib="$dev/Library/Developer"
[ -d "$lib/Frameworks/Testing.framework" ] || exit 0
printf '%s ' -Xswiftc -F -Xswiftc "$lib/Frameworks" \
  -Xlinker -rpath -Xlinker "$lib/Frameworks" -Xlinker -rpath -Xlinker "$lib/usr/lib"
