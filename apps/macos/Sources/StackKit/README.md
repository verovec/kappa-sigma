# StackKit

Preprocessing, ported from the legacy Go engine (`../stacking-astro`, read-only): inspect, calibration
library, Siril driver, grading, multi-night, bundle; GraXpert and StarNet drivers (design §4.1, §4.3).

**State:** the oracle seam (card 0044, `Oracle/`), the Siril driver (0045, `Siril/README.md`) and
inspect (0046, `Inspect/README.md`: folders → classified frames → sets) and calibration (0047,
`Calibration/README.md`: masters, library index, matching). Card 0048 (pipeline) ports against
the same oracles.

**StarNet** (card 0055, `StarNet/`): `StarNetRunner.located(by: HostTools)` → `.missing` (no
binary) or `.cannotRun` (`ExecutableCheck`: an x86_64 build without Rosetta) as
`StarNetError`, never a fallback; `starless(of:in:onProgress:)` writes a 16-bit TIFF, runs it,
reads the TIFF back (`ImageImport`). `StarNetCLI` probes `--machine-info` for the StarNet2 flag
CLI (`-i/-o`) vs StarNet++ positional; `StarNetProgress` reads every `N.N%` in the unbroken
`Working: 8.3%Working: 16.7%…` stream. No starless cache yet (legacy `starlessTIFF` reuse).

## Oracle cases

A case is one run of the legacy engine recorded by `../stacking-astro/cmd/oraclerec`, with the
deterministic golden preset (AI, external tools, colour calibration, previews and supervisor off;
Go denoise and trail mask off), so masters are Siril's bytes. Its `record/` folder holds text only:

| File | What it pins |
|---|---|
| `manifest.json` | Siril version, timezone of night keys, legacy commit, sha256 of every file below |
| `inventory.json` | frame classification, sessions, frame sets (`inspect.ScanMany`) |
| `calibration.json` | masters built, and the ones each channel / night group was calibrated with |
| `scripts/NNNN_<dir>.ssf` | every Siril script, in emission order (`<dir>` = Siril's `-d` folder) |
| `grades.json` | per-frame metrics per channel |
| `selection.json` | kept / rejected frames with reasons, counts, the scripts' `unselect`s |
| `registration.json` | anchor night, per-night rotation / overlap, pre-rejects, the scripts' `setref`s |
| `masters.sha256`, `bundle_layers.sha256` | sha256 of each FITS **data unit** (Siril stamps a date in headers) |
| `run.json`, `steps.txt` | the normalized run result and first-seen progress steps |

Paths are normalized: `<ROOT>` (the case folder), `<CAPTURES>` (`~/Documents/astro/captures`),
`<RUN>` (the run id). `OracleCase.load` verifies every hash of the manifest before decoding.

| Case | Input | Where |
|---|---|---|
| `golden-single-night` | synthetic L/R/G/B, one night | committed: `Tests/StackKitTests/Fixtures/oracle/` |
| `golden-two-night` | synthetic, a second night rotated 35° | committed |
| `m31-db` | `M31-DB/{lights,darks,flats,bias}` | live: `~/Documents/astro/fixtures/oracle/` |
| `m31-bb-db` | `M31-DB` + `M31-BB` (not `large-field/`) | live |

The recorder also keeps each case's `in/` (synthetic frames) and `out/` (masters, layers) next to
`record/` under `~/Documents/astro/fixtures/oracle/<case>/`: pixels, never in a repo.

**Known drift (2026-10-20):** the legacy repo's pinned single-night golden predates host Siril 1.4.4
and its own test fails; re-pinning it yields files byte-equal to `golden-single-night`. The
manifest's `legacy_golden` records the comparison.

## Re-record

```sh
cd ../stacking-astro
go run ./cmd/oraclerec --case a,b     # synthetic, seconds
go run ./cmd/oraclerec --case c,d     # real M31, ~1 min and ~15 min, up to ~100 GB scratch (freed)
cp -R ~/Documents/astro/fixtures/oracle/golden-*/record \
  ../kappa-sigma/apps/macos/Tests/StackKitTests/Fixtures/oracle/<case>   # one per synthetic case
```

Re-recording is a contract change: the PR that commits new fixtures says why (`Test-change:`).

## How to extend

- A port loads its case with `OracleCase.load` and compares: bytes for scripts and Siril masters,
  `meanAbs`/`maxAbs`/PSNR with a written tolerance for anything numeric (testing-conventions.md).
- Live cases go in `Live…` suites with `.liveFixtures`, `.tags(.live)`; find them with
  `OracleLiveCases.find` (tests).
- Host tools run through swift-subprocess; a missing tool is a typed error, never a fallback (R2).
- Allowed dependencies: `ImageKit`, `ProjectKit` (`Tests/TestSupport/BoundaryRules.swift`).
