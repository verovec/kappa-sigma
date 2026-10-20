#!/usr/bin/env bash
# Records the FITS oracle of card 0041: Siril's own `stat` of every layer of one legacy run, plus
# each file's sha256, into a pixel-free JSON committed under apps/macos/Tests/ImageKitTests/Fixtures.
# Siril wrote these files, so its statistics are the reference ImageKit's reader must agree with
# (LiveFITSOracleTests). Siril prints means/min/max ×65535 with one decimal — the test tolerance.
# Usage: scripts/record-fits-oracle.sh [run dir] [output json]
# No pipefail: `… | head -1` closes its pipe early on purpose (SIGPIPE upstream is expected).
set -eu
run="${1:-$HOME/Documents/astro/runs/M_31/20261018_191749}"
out="${2:-apps/macos/Tests/ImageKitTests/Fixtures/m31-run-layers.json}"
siril="${SIRIL_CLI:-/Applications/Siril.app/Contents/MacOS/siril-cli}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

version="$("$siril" --version 2>/dev/null | grep -iE '^siril [0-9]' | head -1)"
entries=()
for file in "$run"/*.fits; do
  name="$(basename "$file")"
  printf 'requires 1.2.0\nload "%s"\nstat\n' "$file" > "$work/stat.ssf"
  log="$("$siril" -d "$work" -s "$work/stat.ssf" 2>&1)"
  dims="$(printf '%s\n' "$log" | grep -oE '[0-9]+x[0-9]+ pixels' | head -1 | cut -d' ' -f1)"
  channels="$(printf '%s\n' "$log" | grep -E 'Mean|Moyenne' | while read -r line; do
    # After the channel label: mean, median, sigma, min, max, bgnoise (French or English log).
    nums=($(printf '%s\n' "${line#*:*:}" | grep -oE '[-]?[0-9]+(\.[0-9]+)?'))
    printf '{"mean": %s, "min": %s, "max": %s}\n' "${nums[0]}" "${nums[3]}" "${nums[4]}"
  done | paste -sd, -)"
  sha="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  entries+=("{\"name\": \"$name\", \"sha256\": \"$sha\", \"width\": ${dims%x*}, \"height\": ${dims#*x}, \"channels\": [$channels]}")
  echo "recorded $name ($dims)" >&2
done

{
  printf '{\n  "run": "%s",\n  "siril": "%s",\n  "scale": 65535,\n  "tolerance": 0.05,\n  "files": [\n' \
    "${run#"$HOME"/Documents/astro/runs/}" "$version"
  for i in "${!entries[@]}"; do
    sep=","; [ "$i" -eq $((${#entries[@]} - 1)) ] && sep=""
    printf '    %s%s\n' "${entries[$i]}" "$sep"
  done
  printf '  ]\n}\n'
} > "$out"
echo "wrote $out" >&2
