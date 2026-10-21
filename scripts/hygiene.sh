#!/usr/bin/env bash
# Repo hygiene gate (CLAUDE.md "Language policy" + "Data lives outside every repo", card 0064).
# Fails when a TRACKED file violates a structural rule. Card 0064 ports this to a Swift test;
# until then this script is what `just hygiene` and CI run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
report() { printf '  ✗ %s\n' "$1"; fail=1; }

echo "hygiene: tracked files"
files="$(git ls-files)"

# 1. Swift only — no second language, no container.
bad=$(printf '%s\n' "$files" | grep -E '(^|/)(go\.mod|go\.sum|Dockerfile|docker-compose\.ya?ml|compose\.ya?ml|requirements\.txt|pyproject\.toml|package\.json)$|\.(go|py|cgo|js|ts)$' \
  | grep -vE '^(docs|tasks-context|conventions)/' || true)
[ -z "$bad" ] || report "non-Swift code or container files tracked:"$'\n'"$bad"

# 2. Nothing pixel-shaped — fixtures in the repo are text only.
bad=$(printf '%s\n' "$files" | grep -iE '\.(fits?|fts|xisf|tiff?|png|jpe?g|cr[23]|nef|arw|dng|raw|seq)$' || true)
[ -z "$bad" ] || report "pixel-shaped files tracked (R7):"$'\n'"$bad"

# 3. No data symlinks or data folders recreated inside the repo.
for d in input output library captures runs work; do
  if [ -L "$d" ] || [ -d "$d" ]; then report "'$d/' exists at the repo root (data lives in ~/Documents/astro)"; fi
done
bad=$(git ls-files -s | awk '$1 == "120000" { print $4 }' || true)
[ -z "$bad" ] || report "symlinks tracked:"$'\n'"$bad"

# 4. Large blobs never belong in git (goldens live outside, manifests inside).
# wc -c rather than stat: BSD and GNU stat disagree on flags, this job also runs on Linux.
bad=$(git ls-files -z | xargs -0 wc -c | awk '$2 != "total" && $1 > 2000000 { print $2 " (" $1 " bytes)" }' || true)
[ -z "$bad" ] || report "files over 2 MB tracked:"$'\n'"$bad"

# 5. The planning state stays local (gitignored by design).
bad=$(printf '%s\n' "$files" | grep -E '^(roadmap\.md|cards/|stacking-doc\.md)' || true)
[ -z "$bad" ] || report "local planning files tracked:"$'\n'"$bad"

# 6. No enum raw value shown as a label (card 0074): a word on screen comes from the glossary
#    (HelpKit) or a string catalog, so it exists in French and English.
views=$(printf '%s\n' "$files" | grep -E '^apps/macos/Sources/(AstroStackApp|RenderKit)/.*\.swift$' || true)
#    Caught: a raw value passed to a view or catalog call, interpolated into a string, or
#    capitalized for display.
bad=$( [ -z "$views" ] || printf '%s\n' "$views" | tr '\n' '\0' | xargs -0 grep -nHE \
  '(Text|Label|Button|LabeledContent|\.app|\.renderKit)\(.*rawValue|\\\([^)]*rawValue|rawValue\.capitalized' \
  || true)
[ -z "$bad" ] || report "enum raw values shown as labels (use AppGlossary or the catalog):"$'\n'"$bad"

# 7. No ad-hoc status colours in views (card 0075): colours come from RenderKit's DesignColor
#    tokens, which keep contrast in light and dark and a neutral image surround.
bad=$( [ -z "$views" ] || printf '%s\n' "$views" | tr '\n' '\0' | xargs -0 grep -nHE \
  'Color\.(red|orange|yellow|green|blue|gray|black)\b|(foregroundStyle|tint|fill|stroke|background)\(\.(red|orange|yellow|green|blue|gray|black)\b|NSColor\.system(Red|Orange|Yellow|Green|Blue)\b' \
  || true)
[ -z "$bad" ] || report "literal colours in views (use DesignColor tokens):"$'\n'"$bad"

if [ "$fail" -ne 0 ]; then echo "hygiene: FAILED"; exit 1; fi
echo "hygiene: ok"
