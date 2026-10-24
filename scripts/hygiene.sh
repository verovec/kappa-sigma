#!/usr/bin/env bash
# Repo hygiene gate (CLAUDE.md "Language policy" + "Data lives outside every repo", card 0064).
# Fails when a TRACKED file violates a structural rule. The rules live here only: `just hygiene`
# and both CI jobs run this script (the Linux one has no Swift), and
# apps/macos/Tests/TestSupportTests/RepoHygieneTests.swift pins each rule on a fixture tree.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
report() { printf '  ✗ %s\n' "$1"; fail=1; }

echo "hygiene: tracked files"
files="$(git ls-files)"
# Membership in the tracked list. Never `printf … | grep -q`: grep stops at the match, the killed
# writer fails the pipe under pipefail, and the test reads false on a long list
# (RepoHygieneTests.testNoForbiddenArtifacts_largeTree).
tracked() { grep -qxF "$1" <<<"$files"; }

# 1. Swift only — no second language, no container.
bad=$(printf '%s\n' "$files" | grep -E '(^|/)(go\.mod|go\.sum|Dockerfile|docker-compose\.ya?ml|compose\.ya?ml|requirements\.txt|pyproject\.toml|package\.json)$|\.(go|py|cgo|js|ts)$' \
  | grep -vE '^(docs|tasks-context|conventions)/' || true)
[ -z "$bad" ] || report "non-Swift code or container files tracked:"$'\n'"$bad"
#    No web front end either, at any depth, whatever it holds (the legacy Vue app is never migrated).
bad=$(printf '%s\n' "$files" | grep -E '(^|/)frontend/' || true)
[ -z "$bad" ] || report "'frontend/' tracked (the app is SwiftUI only):"$'\n'"$bad"

# 2. Nothing pixel-shaped: fixtures in the repo are text only. The one exception is the README's
#    artwork in docs/assets/ (card 0082): web images only, each at most 600 KB. Data never goes there.
pixels='\.(fits?|fts|xisf|tiff?|png|jpe?g|webp|cr[23]|nef|arw|dng|raw|seq)$'
bad=$(printf '%s\n' "$files" | grep -iE "$pixels" | grep -vE '^docs/assets/[^/]+\.(png|jpe?g|webp)$' || true)
[ -z "$bad" ] || report "pixel-shaped files tracked (R7):"$'\n'"$bad"
art=$(printf '%s\n' "$files" | grep -E '^docs/assets/' || true)
bad=$( [ -z "$art" ] || printf '%s\n' "$art" | tr '\n' '\0' | xargs -0 wc -c \
  | awk '$2 != "total" && $1 > 600000 { print $2 " (" $1 " bytes)" }' || true)
[ -z "$bad" ] || report "README artwork over 600 KB:"$'\n'"$bad"

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

# 8. Every relative link in the README and docs/ resolves (card 0082).
bad=$(./scripts/check-links.sh || true)
[ -z "$bad" ] || report "broken relative links:"$'\n'"$bad"

# 9. The tracked French README mirrors the English one (card 0064): as many `## ` sections outside
#    code fences, and the same commands in its ```bash blocks. Comments (after two spaces or more)
#    are translated, so they are dropped first; other blocks, such as the stage diagram, are prose.
commands() {
  awk '/^```bash/ { inside = 1; next } /^```/ { inside = 0 } inside' "$1" | sed -E 's/[[:space:]]{2,}#.*$//'
}
sections() { awk '/^```/ { fenced = !fenced; next } !fenced && /^## / { n++ } END { print n + 0 }' "$1"; }
if tracked README.fr.md; then
  # Both tracked and both on disk, or the comparison would read a missing file.
  missing=""
  for page in README.md README.fr.md; do
    { tracked "$page" && [ -f "$page" ]; } || missing="$missing $page"
  done
  if [ -n "$missing" ]; then
    report "README.fr.md is tracked, but not tracked and on disk:$missing"
  else
    [ "$(commands README.md)" = "$(commands README.fr.md)" ] \
      || report "README.fr.md commands differ from README.md (translate the comments only)"
    en=$(sections README.md) fr=$(sections README.fr.md)
    [ "$en" = "$fr" ] || report "README.fr.md has $fr sections, README.md has $en"
  fi
fi

if [ "$fail" -ne 0 ]; then echo "hygiene: FAILED"; exit 1; fi
echo "hygiene: ok"
