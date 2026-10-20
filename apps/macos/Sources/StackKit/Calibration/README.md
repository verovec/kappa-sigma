# StackKit / Calibration

Masters and their matching (card 0047): port of the legacy `internal/calib`, pinned by every
0044 oracle case — the `cal_master_*.ssf` scripts byte for byte, and `calibration.json` (masters
built, each light set's bias/dark/flat, per-night groups).

## Pieces

| Type | Legacy | What it does |
|---|---|---|
| `MasterName` | `masterName` | the file-name grammar, both ways: the library's only key |
| `CalibrationMaster` | `calib.Master` | a master; `satisfies(_:)` = `masterMatchesSet` (night-stamped flats need their own night) |
| `CalibrationMatcher` | `match.go` | exact dark ±5 °C → `-opt` dark with a bias → forced; flats by filter, then night (nearest), camera, depth; filter-set gate; exclusions by `suggestionID` |
| `LightRef` | `LightRef`, `RefFor` | a light set and its clip filter (set verdict, else its night's) |
| `DimensionGuard` | `dims.go` | drops masters of another sensor from the POOL (Siril silently skips a wrong-size master) |
| `CalibrationPreview` | `suggest.go` | candidates (library ∪ masters the run would build) and per-channel suggestions |
| `PoolSignature` | `poolsig`, `.sig` | which frames a master was stacked from: reuse only when proven |
| `CalibrationLibrary` | `library.go` + Postgres index | indexes `~/Documents/astro/library` into `project.db` (`calibration_masters`, migration 0002); the folder is the truth |
| `MasterBuilder` | `BuildMasters`, `BuildOrReuseMasters` | bias → dark-flat → dark → flat through Siril (0045 scripts); `.direct` into a run folder, `.atomic` (`.tmp_<run>_<name>` + rename) into the library; `.sig` written once the master is in place |
| `MasterStats`, `MasterWarning`, `MasterInspection` | `calibscan` (one-off audit) | a master's median, σ (MAD), min/max, quadrants, corner/centre (flats), clipped %, hot pixels (darks); the documented thresholds it crosses (card 0071) |

## Rules worth knowing

- Master statistics are measured, shown and never acted on (R2). Sampling steps are odd and the
  vignetting is taken on 2×2 block means: an even step reads ONE Bayer colour per patch, which
  made a dual-band OSC flat read "+59 % brighter corners" (it is −3 %). Thresholds:
  `MasterWarning` (corners brighter than centre; flat median < 10 % of full scale — M 45's
  corrupted lot sat at 6 %; > 0.1 % clipped; dark hot pixels > 0.5 %).
- `MasterBuilder.rebuild` stacks one set straight into the library (`.atomic`); `onLine` streams
  Siril's lines (progress) for every build.

- R2: every fallback is a note (`no L flat — using the session flat…`, cross-night, forced,
  borrowed from the library, cross-set refusal); nothing is applied silently.
- A dual-band night never gets a broadband flat when both filter sets are known; `force` is the
  only way past it, and it says so (memory `flat-matching-pitfalls`). Library flats come back
  set-blind (no filter-set column, as in the legacy index), so the gate cannot fire on them: only
  this run's own flats carry their night's verdict.
- An undated flat ranks below every dated one on a multi-night run, but is still a last resort.
- Library masters are night-blind unless their name carries `_n<night>`.

## Deliberate departures from the legacy engine (review of 0047)

- Excluding the bias of a `-opt` selection drops its dark too, with a note: Go kept the
  different-exposure dark and subtracted it unscaled, a calibration the panel never showed.
- The preview counts a library master as reused only when the run would reuse it (default
  recipe, `.sig` proving the same frames); Go reused on fields alone and could show a master the
  run then rebuilt.
- Reuse requires the same recipe tag; a master's `.sig` is written after the master is in place
  (the old one removed first), so a failed publish can only cause a rebuild.

## Not ported (yet)

- Deep masters pooled from a raw-frame catalogue (`deep.go`): no catalogue exists in the app.
- Dark defect lists (`-cc=bpm`) and flat QC (`flatqc`, `optics`): side outputs, unused by the
  oracle path (`-cc=dark`); master inspection is card 0071.
- Phone/DSLR matching (`phone.go`): deep-sky only.
- Recipe fingerprints are this port's own (sha256 of the options, 3 bytes): a non-default recipe
  never shares a name with the default master, but its tag differs from the Go one.

## How to extend

- A new rule: a translated table case first in `CalibrationMatcherTests`, then the code.
- A new master field in the index: a new migration pair (never edit 0002), `CalibrationMasterRow`,
  `CalibrationLibrary.row`, `SCHEMA.md`.
- Scripts come from `SirilScripts`; a new verb needs a `SirilCommand` sample (live grammar test).
