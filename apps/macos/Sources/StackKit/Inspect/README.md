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

The walk (`InspectWalk`) skips hidden folders, `output/` folders and, since card 0101, **package
folders**: a `.astrostack` project (by extension, Launch Services may not know it) or anything the
Finder shows as a package. Their FITS are never frames (a project's stacks have no OBJECT and
read as a second object); each one lands in `Inventory.skipped` (relative to the root) with a
`skip <path>: a package …` warning the import sheet shows. A new kind of folder to keep out of a
scan is a rule in `InspectWalk.visit` plus a row in `InventoryBuilderTests+Packages`.

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

Phone/DSLR raws, TIFF/JPEG stills, videos and the scan cache: deep-sky FITS only.
Go's unstable sorts are made deterministic (set ties: bin, colour, temperature; session configs:
offset, bin, warmer first).

## Oracles

- `InventoryOracleTests` (CI): the synthetic cases rebuilt from committed headers
  (`Tests/StackKitTests/Fixtures/inspect/<case>.headers.json`) compared field by field with
  `inventory.json` (`InventoryJSON` writes ours in the legacy JSON shape).
- `LiveInventoryOracleTests`: the real `in/` frames, and the M31-DB / M31-BB+DB captures (~90 s).
  `RECORD=1` rewrites the header fixtures from `~/Documents/astro/fixtures/oracle/<case>/in`.

## S3 remote scan (card 0167)

- `RemoteScan(store:prefix:timeZone:).inventory()` scans an S3 prefix with today's synchronous
  scan over a `RemoteSnapshot` (`Remote/`): the listing (`InspectWalk.listing(keys:under:)`, the
  local walk's rules over keys), every FITS header read by ranges grown until `END`, the small
  side files (sidecars, `info.txt`). Paths are virtual: `s3://<bucket>/<key>` (`PathMeta` skips
  the scheme and bucket).
- Pixels: a first pass records the centred runs the scan asks for; they are read by range
  (`FITSFile.centerRun` / `physicalValues`) and the scan runs again. Whole frames are never
  downloaded (PO 01/11): a check that asks for planes is not run; the frames its verdict spans
  (`RemoteScan.unchecked`: the set of a missed read, the instrument of a CFA probe, every light
  when the bias/dark pedestal was asked) are listed in `Inventory.notCheckedRemotely` — the
  Données line « non vérifié (distant) », never a pass. A side file that fails is a warning.
- Several roots scan as one capture (card 0190): `CaptureScan(roots:timeZone:).scan()` takes
  folders of this Mac and bucket prefixes in one ordered list, loads one `RemoteSnapshot` per
  prefix, and runs the synchronous scan once over them all through a composite `FrameSource` /
  `PixelReader` (a path under a prefix's root is read from its snapshot, the deepest when prefixes
  nest; anything else from disk). Grouping and verdicts therefore see the union: the darks of a
  calibration prefix serve the lights of another prefix or of a folder. `RemoteScan` is the
  one-prefix case of it. A prefix that cannot be read fails the whole scan, never the other roots
  alone (R2). `Scanned.caches` answers what was read of each prefix, by its root.
- A rescan reads only what changed (card 0168): `RemoteScan.scan(cache:)` answers `Scanned`
  (inventory + `RemoteScanCache`), the cache being key -> (ETag, size, header cards, side-file
  bytes) for the files the walk just answered. `RemoteSnapshot.load(store:prefix:cache:)` seeds
  from it when the ETag and size still match and reads everything else; a key the bucket no longer
  holds, and anything the walk skips (`output/`, an orphan sidecar), is in neither the inventory
  nor the next cache. The centred pixel runs are **not** cached — 200 000 values a frame would put
  hundreds of megabytes of JSON in `project.db`; they are re-read by range, one request per frame.
  The project keeps the body (`ProjectStore.setRemoteScan`), and `inventory()` is the same scan
  with the cache discarded.
- StackKit never imports RemoteKit: `RemoteObjectStore` is two closures; the app adapts its
  `S3Client` (`RemoteObjectStore.s3(_:bucket:)`). Tests use an in-memory store
  (`Tests/.../Remote/MemoryStore.swift`) and the oracle trees (`RemoteScanTests`).

## How to extend

- A filter name: only in FilterKit's `Filter` (the one list, pinned by `FilterKitTests.FilterTests`; `FilterSet` lives there too).
- Pixels go through `PixelReader` (`.files` uses ImageKit); tests inject planes and samples.
- Everything else the scan reads goes through `FrameSource` (card 0166): `listing` (the walk),
  `header` (a frame's primary header), `contents` (a sidecar, an `info.txt`). `.files` is the local
  disk; `InventoryBuilder(timeZone:pixels:source:)` takes another (the S3 snapshot of 0167, tests'
  in-memory trees — `FrameSourceTests`). Never read the disk directly from a scan step.
- A new verdict that reads pixels must be overridable in `InspectOverrides` and stay `unknown`
  when it cannot decide.
