#!/usr/bin/env bash
# Records the finishing oracles (card 0067): the PO's validated v9 "HaPlus" chain on run #78
# (M_31/20261018_191749) and on a 1024×768 centre crop of its layers, into
# ~/Documents/astro/fixtures/finish/ with SHA256SUMS and manifest.json. Nothing is written into
# a repo or into the run folder; the Go tools are built from copies kept in the fixtures folder
# (kappa-sigma's gitignored tasks-context/tools + the legacy internal/imgops, read only).
#
# Usage: scripts/record-finish-oracle.sh   (Go, Siril 1.4, /usr/local/bin/starnet2)
#   KAPPA_TOOLS   tasks-context/tools of the main checkout (default: next to this script's repo)
# Then:  cp ~/Documents/astro/fixtures/finish/manifest.json apps/macos/Tests/TestSupport/Fixtures/finish/
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tools="${KAPPA_TOOLS:-$repo/tasks-context/tools}"
legacy="${LEGACY_IMGOPS:-$HOME/Documents/dev/projects/stacking-astro/internal/imgops}"
run="$HOME/Documents/astro/runs/M_31/20261018_191749"
out="$HOME/Documents/astro/fixtures/finish"
siril="${SIRIL_BIN:-/Applications/Siril.app/Contents/MacOS/siril-cli}"
starnet="${STARNET_BIN:-/usr/local/bin/starnet2}"
[ -f "$tools/astrocomp/main.go" ] || { echo "no tools at $tools (set KAPPA_TOOLS)"; exit 1; }

# Chain flags (v9compose.sh, PO choices of 19-10: HaPlus, HDR t1/s from the absolute sky offsets).
hdr_flags=(-t1 1.064 -s 0.090 -sigma 30)
comp_flags=(-coverage-crop -crop 0.005 -base-bg 0.085 -ha-bg 0.12 -ha-black 0.115
  -ha-screen 0.95 -oiii-bg 0.12 -oiii-black 0.126 -oiii-screen 0.80 -oiii-boost 1.25
  -star-radius 4 -layer-smooth 0 -sat-masked)
stark=0.25
crop=(2612 1704 1024 768)   # centre of 6248×4176: ((6248 − 1024) / 2, (4176 − 768) / 2)

echo "▶ build the tools (copies only)"
rm -rf "$out/tools-src" "$out/bin" "$out/full" "$out/crop"
mkdir -p "$out/tools-src" "$out/bin" "$out/full" "$out/crop"
for tool in astrocomp hdrcomp stardesat desat; do
  mkdir -p "$out/tools-src/$tool"
  cp "$tools/$tool/main.go" "$out/tools-src/$tool/main.go"
  printf 'module finish/%s\n\ngo 1.22\n' "$tool" > "$out/tools-src/$tool/go.mod"
done
mkdir -p "$out/tools-src/hdrcomp/imgops"
cp "$legacy"/{blur,median,morph,resample,stats}.go "$out/tools-src/hdrcomp/imgops/"
sed -i '' 's#"github.com/verove-jordan/astronomy/internal/imgops"#"finish/hdrcomp/imgops"#' \
  "$out/tools-src/hdrcomp/main.go"
for tool in astrocomp hdrcomp stardesat desat; do
  (cd "$out/tools-src/$tool" && GOFLAGS=-mod=mod GOPROXY=off go build -o "$out/bin/$tool" .)
done
bin="$out/bin"

echo "▶ centre crop of the three layers (Siril)"
for layer in rgb_base syn_Ha syn_OIII; do cp "$run/$layer.fits" "$out/full/$layer.fits"; done
{
  echo "requires 1.4.0"; echo "setext fits"
  for layer in rgb_base syn_Ha syn_OIII; do
    echo "load $out/full/$layer.fits"; echo "crop ${crop[*]}"; echo "save $layer"
  done
} > "$out/crop/crop.ssf"
"$siril" -d "$out/crop" -s "$out/crop/crop.ssf" > "$out/crop/crop.log" 2>&1
rm "$out/crop/crop.ssf"

chain() { # $1 = folder holding rgb_base / syn_Ha / syn_OIII
  (cd "$1"
    "$bin/hdrcomp" -in rgb_base.fits -out hdr_only.fits "${hdr_flags[@]}"
    "$bin/astrocomp" -base hdr_only.fits -ha syn_Ha.fits -oiii syn_OIII.fits "${comp_flags[@]}" \
      -sat 0 -out screens_only.png
    "$bin/astrocomp" -base hdr_only.fits -ha syn_Ha.fits -oiii syn_OIII.fits "${comp_flags[@]}" \
      -sat 0.32 -out haplus_full.png
    "$starnet" --input haplus_full.png --output starless.png
    "$bin/stardesat" haplus_full.png starless.png haplus_final.png "$stark" 1.0
    for r in 25 50 75; do
      "$bin/stardesat" haplus_full.png starless.png "stars_$r.png" "$stark" "0.$r"
    done
  ) > "$1/chain.log" 2>&1
}
echo "▶ chain on the full frame"; chain "$out/full"
echo "▶ chain on the crop"; chain "$out/crop"
rm "$out/full"/{rgb_base,syn_Ha,syn_OIII}.fits   # the full layers stay in the run folder

echo "▶ SHA256SUMS + manifest.json"
(cd "$out" && find full crop tools-src -type f \( -name '*.fits' -o -name '*.png' -o -name '*.go' \) \
  | sort | xargs shasum -a 256 > SHA256SUMS)
sha() { shasum -a 256 "$out/$1" | cut -d' ' -f1; }
dims() { # "width height" of a PNG (sips) or FITS (NAXIS1/2)
  case "$1" in
    *.png) sips -g pixelWidth -g pixelHeight "$out/$1" | awk '/pixel/ {printf "%s ", $2}' ;;
    *.fits) head -c 2880 "$out/$1" | fold -w 80 | awk -F'[=/]' '/^NAXIS[12] / {gsub(/ /,"",$2); printf "%s ", $2}' ;;
    *) echo "0 0" ;;
  esac
}
file_json() { local d; d=($(dims "$1")); printf '{"path": "%s", "sha256": "%s", "width": %s, "height": %s}' "$1" "$(sha "$1")" "${d[0]:-0}" "${d[1]:-0}"; }
args_json() { local first=1; printf '['; for a in "$@"; do [ $first = 1 ] || printf ', '; first=0; printf '"%s"' "$a"; done; printf ']'; }
stage_json() { # name tool ext inputs-json flags...
  local name="$1" tool="$2" ext="$3" inputs="$4"; shift 4
  printf '    {"name": "%s", "tool": "%s", "flags": %s, "inputs": %s,\n     "outputs": [%s, %s]}' \
    "$name" "$tool" "$(args_json "$@")" "$inputs" "$(file_json "full/$name.$ext")" "$(file_json "crop/$name.$ext")"
}
tools_json() { local first=1; for f in $(cd "$out" && find tools-src -name '*.go' | sort); do
  [ $first = 1 ] || printf ', '; first=0; file_json "$f"; done; }
{
  printf '{\n  "provenance": {"run": "M_31/20261018_191749", "runNumber": 78, "recorded": "%s",\n' "$(date +%F)"
  printf '    "chain": "v9 HaPlus: hdrcomp → astrocomp → starnet2 → stardesat",\n'
  printf '    "versions": {"go": "%s", "siril": "%s", "starnet2": "%s"},\n' \
    "$(go version | cut -d' ' -f3)" "$("$siril" --version 2>/dev/null | head -1 | tr -d '"')" "user install ($starnet)"
  printf '    "tools": [%s]},\n' "$(tools_json)"
  printf '  "crop": {"x": %s, "y": %s, "width": %s, "height": %s},\n' "${crop[@]}"
  printf '  "layers": [%s, %s, %s],\n' "$(file_json crop/rgb_base.fits)" "$(file_json crop/syn_Ha.fits)" "$(file_json crop/syn_OIII.fits)"
  printf '  "stages": [\n'
  stage_json hdr_only hdrcomp fits '["rgb_base.fits"]' -in rgb_base.fits -out hdr_only.fits "${hdr_flags[@]}"; printf ',\n'
  stage_json screens_only astrocomp png '["hdr_only.fits", "syn_Ha.fits", "syn_OIII.fits"]' "${comp_flags[@]}" -sat 0; printf ',\n'
  stage_json haplus_full astrocomp png '["hdr_only.fits", "syn_Ha.fits", "syn_OIII.fits"]' "${comp_flags[@]}" -sat 0.32; printf ',\n'
  stage_json starless starnet2 png '["haplus_full.png"]'; printf ',\n'
  stage_json haplus_final stardesat png '["haplus_full.png", "starless.png"]' "$stark" 1.0
  for r in 25 50 75; do
    printf ',\n'; stage_json "stars_$r" stardesat png '["haplus_full.png", "starless.png"]' "$stark" "0.$r"
  done
  printf '\n  ]\n}\n'
} > "$out/manifest.json"
echo "done: $out/manifest.json"
