# StackKit / Inspect

Capture folders → classified frames → frame sets (card 0046). Port of the legacy
`internal/inspect`, `internal/filters` and `internal/channeldetect`, pinned by the recorded
`inventory.json` of every oracle case (`Oracle/`).

## Entry point

```swift
let inventory = try InventoryBuilder(timeZone: site).scan(paths: folders, overrides: overrides)
```

One folder is its own root; several merge under their common parent, and grouping, verdicts and
completeness warnings run once over the union (calibration in one folder satisfies lights in
another). `timeZone` decides each frame's observing night (local noon bucket); the oracles were
recorded in `Europe/Paris`.

`scan(paths:overrides:progress:)` reports `ScanProgress` (card 0083): the FITS total once every
folder is walked, the count read every 32 files and on the last, then `classifying` before the
union steps. Observation only: the inventory is the same with or without it (pinned by
`InventoryBuilderTests.testScanReportsProgress`). `ImportPlanner.plan` forwards it; the app adds
`.library` while the calibration library is indexed.

## How a frame is decided (precedence, same as Go)

1. **Header** (`CaptureFrame+Header`): IMAGETYP, FILTER (via `Filter`), EXPTIME/EXPOSURE/EXPOINUS,
   GAIN (`hasGain` separates a real 0), OFFSET, EGAIN, CCD-TEMP, binning, BAYERPAT, NAXIS3, DATE-OBS.
2. **Names** (`CaptureFrame+Path`): the SharpCap `<frame>.txt` sidecar (`SharpcapSidecar`), then
   file and folder tokens (`PathMeta`) — only blanks are filled.
3. **`info.txt` manifests** (`CaptureManifest`) and **physical wheel slots** (`WheelSlots`).
4. **Pixel curves** (`FrameClassifier.byStats` over `SampleStats` of the centre run that
   `FITSFile.centerSample` reads) for frames still unknown.
5. **Wheel-order detection** (`ChannelDetector`) for unlabeled mono lights; wheel-transition flags.

Then, once: the per-instrument spurious-BAYERPAT veto (`CFAProbe`), the colour verdict, `RGB`
naming, `FrameSet.group` (temperature clusters, per-night lights/flats when several nights),
user exclusions and filter map, dual-band/broadband verdicts per OSC light set
(`FilterSetClassifier`, electrons above the bias pedestal), sessions, warnings, the colour choice.

## Overrides (R2: visible, and they win)

`InspectOverrides`: `excludeSets` (set ids, applied before `filterMap`), `filterMap`
(`ignore` drops lights), `filterSets` (per light set id), `colorModel` (`auto|mono|osc`),
`detectChannels`. Set ids (`SetKey.id`) are a stored contract: never change their format.

## Not ported

Phone/DSLR raws, TIFF/JPEG stills, videos, the S3 remote scan and the scan cache: deep-sky FITS only.
Go's unstable sorts are made deterministic (set ties: bin, colour, temperature; session configs:
offset, bin, warmer first).

## Oracles

- `InventoryOracleTests` (CI): the synthetic cases rebuilt from committed headers
  (`Tests/StackKitTests/Fixtures/inspect/<case>.headers.json`) compared field by field with
  `inventory.json` (`InventoryJSON` writes ours in the legacy JSON shape).
- `LiveInventoryOracleTests`: the real `in/` frames, and the M31-DB / M31-BB+DB captures (~90 s).
  `RECORD=1` rewrites the header fixtures from `~/Documents/astro/fixtures/oracle/<case>/in`.

## How to extend

- A filter name: only in `Filter` (the one list, pinned by `FilterTests`).
- Pixels go through `PixelReader` (`.files` uses ImageKit); tests inject planes and samples.
- A new verdict that reads pixels must be overridable in `InspectOverrides` and stay `unknown`
  when it cannot decide.
