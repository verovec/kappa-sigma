# ImageKit

Images as data: FITS I/O, planar float32 images, mip pyramid, 16-bit export (design §4.5b, §4.6).
No UI, no Metal: RenderKit uploads what ImageKit produces.

## What exists (card 0041)

- `FITSFile` reads a primary HDU (2880-byte blocks, 80-char cards kept verbatim) and decodes BITPIX
  −32/−64/32/16/8 with BZERO/BSCALE into `AstroImage`, the legacy reader's rules: value =
  BZERO + BSCALE · stored in double, then float32; one or three planes; **rows kept in file order**
  (`metadata.rowOrder` says which way up; the viewer and the export flip, never the planes).
- `write` rewrites a float32 image with the file's own cards: an unchanged image gives the same
  bytes (extensions kept).
- `AstroImage` (non-Sendable class, `planes[c][y * width + x]`), `ImageMetadata` (filter, camera,
  gain, exposure, Bayer pattern, object, row order, plate solution).
- `WCS` (card 0042): the TAN / TAN-SIP solution Siril's solver writes (`CD`, `PC` × `CDELT`, or
  `CDELT` + `CROTA2`; SIP `A_p_q`/`B_p_q` applied before the matrix), array pixel → RA/Dec.
  Pinned within 1″ by an independent tangent-plane vector oracle (`WCSTests`), with run #76's
  solution (SIP shifts its corners by ~2 px, ~6″). Other projections give `nil`, never a guess.
- `KitBundle` (card 0042): a kit's SwiftPM resource bundle from `Contents/Resources` in the app,
  `Bundle.module` otherwise.
- `centerSample(maxCount:)`: the legacy `fits.Stats` read — a contiguous run from the middle of
  the data unit, physical values in double, without decoding the image (inspect, card 0046).
- `Pyramid`: 2×2 block means with vDSP (never stride sampling, so noise stays representative),
  halving until the long side is ≤ 512 px; `build` runs `@concurrent`. 22 Mpx × 3 planes: 0.04 s.
- `ImageExport`: 16-bit TIFF/PNG via ImageIO for deliverables, top row first, values clamped.
- `GridMap` (card 0090): crops, flips and quarter turns as one whole-pixel affine map in 1-based
  FITS coordinates (`p' = M·p + t`, `M` a signed permutation); `FITSHeader.moved(by:)` moves a
  TAN/TAN-SIP solution with it (`CRPIX`, `CD·M⁻¹`, SIP substituted), any other solution is
  dropped; `droppingWCS()` for a resampled frame. Pinned by "every star keeps its RA/Dec".
  `FITSHeader.Card(keyword:value:)` / `(keyword:number:)` build fixed-format cards.

## Oracles

- Unit tests build FITS bytes from the standard (`Tests/ImageKitTests/FITSBytes.swift`), never with
  the writer under test.
- `LiveFITSOracleTests`: the 8 layers of run `M_31/20261018_191749` against Siril's own `stat`
  (`Fixtures/m31-run-layers.json`, re-record with `scripts/record-fits-oracle.sh`): dims,
  per-channel mean/min/max within Siril's one printed decimal (×65535), and a byte-identical
  rewrite. Siril's mean skips null pixels (exactly 0, a stack's black borders); min/max do not.

## How to extend

- CPU-heavy work is `nonisolated` + `@concurrent` and goes through Accelerate; images move with
  `sending`, never `@unchecked Sendable`.
- A new header field: read it in `ImageMetadata(header:)` from `FITSHeader` (cards are verbatim, so
  WCS and anything Siril wrote survive a rewrite).
- Allowed dependencies: none (`Tests/TestSupport/BoundaryRules.swift`).
