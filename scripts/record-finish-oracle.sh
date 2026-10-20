#!/usr/bin/env bash
# Records the finishing oracles (card 0067): the PO's validated v9 "HaPlus" chain on run #78
# (M_31/20261018_191749) and on a 1024×768 centre crop of its layers, into
# ~/Documents/astro/fixtures/finish/ with SHA256SUMS and manifest.json. Nothing is written into
# a repo or into the run folder; the Go tools are built from copies kept in the fixtures folder
# (kappa-sigma's gitignored tasks-context/tools + the legacy internal/imgops, read only).
# Everything is recorded into finish.recording/ and swapped in only on success, so a failed run
# leaves the previous recording intact.
#
# Usage: scripts/record-finish-oracle.sh   (Go, Siril 1.4, /usr/local/bin/starnet2)
#   KAPPA_TOOLS   tasks-context/tools of the main checkout (default: next to this script's repo)
# Then:  cp ~/Documents/astro/fixtures/finish/manifest.json apps/macos/Tests/TestSupport/Fixtures/finish/
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tools="${KAPPA_TOOLS:-$repo/tasks-context/tools}"
legacy="${LEGACY_IMGOPS:-$HOME/Documents/dev/projects/stacking-astro/internal/imgops}"
run="$HOME/Documents/astro/runs/M_31/20261018_191749"
final="$HOME/Documents/astro/fixtures/finish"
out="$final.recording"
siril="${SIRIL_BIN:-/Applications/Siril.app/Contents/MacOS/siril-cli}"
starnet="${STARNET_BIN:-/usr/local/bin/starnet2}"
[ -f "$tools/astrocomp/main.go" ] || { echo "no tools at $tools (set KAPPA_TOOLS)"; exit 1; }

# Chain flags (v9compose.sh, PO choices of 19-10: HaPlus, HDR t1/s from the absolute sky offsets;
# no DESAT for M31 HaPlus). Settings only: inputs and outputs are recorded apart.
hdr_flags=(-t1 1.064 -s 0.090 -sigma 30)
comp_flags=(-coverage-crop -crop 0.005 -base-bg 0.085 -ha-bg 0.12 -ha-black 0.115
  -ha-screen 0.95 -oiii-bg 0.12 -oiii-black 0.126 -oiii-screen 0.80 -oiii-boost 1.25
  -star-radius 4 -layer-smooth 0 -sat-masked)
stark=0.25
# Centre of the 5967×3763 base ((5967 − 1024) / 2, (3763 − 768) / 2); it holds the galaxy core.
# Siril's crop counts y from the top of the displayed image: stored rows start at 3763 − y − 768.
crop=(2471 1497 1024 768)
tools_used=(astrocomp hdrcomp stardesat)

echo "▶ build the tools (copies only)"
rm -rf "$out"
mkdir -p "$out/tools-src" "$out/bin" "$out/full" "$out/crop"
for tool in "${tools_used[@]}"; do
  mkdir -p "$out/tools-src/$tool"
  cp "$tools/$tool/main.go" "$out/tools-src/$tool/main.go"
  printf 'module finish/%s\n\ngo 1.22\n' "$tool" > "$out/tools-src/$tool/go.mod"
done
mkdir -p "$out/tools-src/hdrcomp/imgops"
cp "$legacy"/{blur,median,morph,resample,stats}.go "$out/tools-src/hdrcomp/imgops/"
sed -i '' 's#"github.com/verove-jordan/astronomy/internal/imgops"#"finish/hdrcomp/imgops"#' \
  "$out/tools-src/hdrcomp/main.go"
for tool in "${tools_used[@]}"; do
  (cd "$out/tools-src/$tool" && GOFLAGS=-mod=mod GOPROXY=off go build -o "$out/bin/$tool" .)
done
bin="$out/bin"

echo "▶ centre crop of the three layers (Siril)"
{
  echo "requires 1.4.0"; echo "setext fits"
  for layer in rgb_base syn_Ha syn_OIII; do
    echo "load $run/$layer.fits"; echo "crop ${crop[*]}"; echo "save $layer"
  done
} > "$out/crop/crop.ssf"
"$siril" -d "$out/crop" -s "$out/crop/crop.ssf" > "$out/crop/crop.log" 2>&1
rm "$out/crop/crop.ssf"

chain() { # $1 = output folder, $2 = folder holding rgb_base / syn_Ha / syn_OIII (read only)
  local layers="$2"
  (cd "$1"
    "$bin/hdrcomp" -in "$layers/rgb_base.fits" -out hdr_only.fits "${hdr_flags[@]}"
    "$bin/astrocomp" -base hdr_only.fits -ha "$layers/syn_Ha.fits" -oiii "$layers/syn_OIII.fits" \
      "${comp_flags[@]}" -sat 0 -out screens_only.png
    "$bin/astrocomp" -base hdr_only.fits -ha "$layers/syn_Ha.fits" -oiii "$layers/syn_OIII.fits" \
      "${comp_flags[@]}" -sat 0.32 -out haplus_full.png
    "$starnet" --input haplus_full.png --output starless.png
    "$bin/stardesat" haplus_full.png starless.png haplus_final.png "$stark" 1.0
    for r in 25 50 75; do
      "$bin/stardesat" haplus_full.png starless.png "stars_$r.png" "$stark" "0.$r"
    done
  ) > "$1/chain.log" 2>&1
}
# The full-frame layers are read in place (the run folder is never written).
echo "▶ chain on the full frame"; chain "$out/full" "$run"
echo "▶ chain on the crop"; chain "$out/crop" "$out/crop"

echo "▶ SHA256SUMS + manifest.json"
(cd "$out" && find full crop tools-src -type f \
  \( -name '*.fits' -o -name '*.png' -o -name '*.go' -o -name 'go.mod' \) \
  | sort | xargs shasum -a 256 > SHA256SUMS)
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
dims() { # "width height" of a PNG (sips) or FITS (NAXIS1/2)
  case "$1" in
    *.png) sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {printf "%s ", $2}' ;;
    *.fits) head -c 2880 "$1" | fold -w 80 | awk -F'[=/]' '/^NAXIS[12] / {gsub(/ /,"",$2); printf "%s ", $2}' ;;
    *) echo "0 0" ;;
  esac
}
file_json() { local d; d=($(dims "$out/$1")); printf '{"path": "%s", "sha256": "%s", "width": %s, "height": %s}' "$1" "$(sha "$out/$1")" "${d[0]:-0}" "${d[1]:-0}"; }
args_json() { local first=1; printf '['; for a in "$@"; do [ $first = 1 ] || printf ', '; first=0; printf '"%s"' "$a"; done; printf ']'; }
stage_json() { # name tool ext inputs-json flags...
  local name="$1" tool="$2" ext="$3" inputs="$4"; shift 4
  printf '    {"name": "%s", "tool": "%s", "flags": %s, "inputs": %s,\n     "outputs": [%s, %s]}' \
    "$name" "$tool" "$(args_json "$@")" "$inputs" "$(file_json "full/$name.$ext")" "$(file_json "crop/$name.$ext")"
}
tools_json() { local first=1; for f in $(cd "$out" && find tools-src -type f \( -name '*.go' -o -name 'go.mod' \) | sort); do
  [ $first = 1 ] || printf ', '; first=0; file_json "$f"; done; }
validated_json() { # stage → the PO's run #78 deliverable it reproduces
  local first=1 stage file
  for pair in haplus_final:M31_v9style_hdr_HaPlus.png starless:M31_v9style_hdr_HaPlus_starless.png \
    stars_25:M31_v9style_hdr_HaPlus_stars25.png stars_50:M31_v9style_hdr_HaPlus_stars50.png \
    stars_75:M31_v9style_hdr_HaPlus_stars75.png; do
    stage="${pair%%:*}"; file="${pair#*:}"
    [ $first = 1 ] || printf ',\n'; first=0
    printf '    {"stage": "%s", "deliverable": "%s", "sha256": "%s"}' "$stage" "$file" "$(sha "$run/$file")"
  done
}
{
  printf '{\n  "provenance": {"run": "M_31/20261018_191749", "runNumber": 78, "recorded": "%s",\n' "$(date +%F)"
  printf '    "chain": "v9 HaPlus: hdrcomp → astrocomp → starnet2 → stardesat",\n'
  printf '    "versions": {"go": "%s", "siril": "%s", "starnet2": "%s"},\n' \
    "$(go version | cut -d' ' -f3)" "$("$siril" --version 2>/dev/null | grep -i '^siril [0-9]' | head -1)" "user install ($starnet)"
  printf '    "tools": [%s]},\n' "$(tools_json)"
  printf '  "crop": {"x": %s, "y": %s, "width": %s, "height": %s},\n' "${crop[@]}"
  printf '  "layers": [%s, %s, %s],\n' "$(file_json crop/rgb_base.fits)" "$(file_json crop/syn_Ha.fits)" "$(file_json crop/syn_OIII.fits)"
  printf '  "stages": [\n'
  stage_json hdr_only hdrcomp fits '["rgb_base.fits"]' "${hdr_flags[@]}"; printf ',\n'
  stage_json screens_only astrocomp png '["hdr_only.fits", "syn_Ha.fits", "syn_OIII.fits"]' "${comp_flags[@]}" -sat 0; printf ',\n'
  stage_json haplus_full astrocomp png '["hdr_only.fits", "syn_Ha.fits", "syn_OIII.fits"]' "${comp_flags[@]}" -sat 0.32; printf ',\n'
  stage_json starless starnet2 png '["haplus_full.png"]'; printf ',\n'
  stage_json haplus_final stardesat png '["haplus_full.png", "starless.png"]' "$stark" 1.0
  for r in 25 50 75; do
    printf ',\n'; stage_json "stars_$r" stardesat png '["haplus_full.png", "starless.png"]' "$stark" "0.$r"
  done
  printf '\n  ],\n'
  printf '  "validated": [\n%s\n  ],\n' "$(validated_json)"
  # Render ↔ deliverable: the 19-10 renders differ only by 16-bit rounding (max 0.22/255).
  printf '  "tolerance": {"meanAbs": 0.0039215686, "maxAbs": 0.0039215686}\n}\n'
} > "$out/manifest.json"

# Swap in only now: a failure above left the previous recording untouched.
rm -rf "$final.previous"
[ ! -d "$final" ] || mv "$final" "$final.previous"
mv "$out" "$final"
rm -rf "$final.previous"
echo "done: $final/manifest.json"
