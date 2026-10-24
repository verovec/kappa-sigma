#!/usr/bin/env bash
# Prints every relative link of the tracked Markdown front pages (README*.md, docs/**/*.md) whose
# target does not exist, as `file: target`; prints nothing when all resolve (card 0082).
# URLs, mail links and pure anchors are skipped; `path#anchor` is checked for the path only.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git ls-files 'README*.md' 'docs/*.md' 'docs/**/*.md' | sort -u | while read -r page; do
  dir=$(dirname "$page")
  # Markdown links/images `](target)` and HTML `src="target"` / `href="target"`.
  { grep -oE '\]\([^)[:space:]]+\)' "$page" | sed -E 's/^\]\((.*)\)$/\1/' || true
    grep -oE '(src|href)="[^"]+"' "$page" | sed -E 's/^(src|href)="(.*)"$/\2/' || true
  } | while read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    path=${target%%#*}
    [ -e "$dir/$path" ] || echo "$page: $target"
  done
done
