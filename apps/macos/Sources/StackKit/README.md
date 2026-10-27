# StackKit

Preprocessing, ported from the legacy Go engine (`../stacking-astro`, read-only): inspect, calibration
library, Siril driver, grading, multi-night, bundle; GraXpert and StarNet drivers (design §4.1, §4.3).

**State:** the oracle seam (card 0044, `Oracle/`), the Siril driver (0045, `Siril/README.md`) and
inspect (0046, `Inspect/README.md`: folders → classified frames → sets) and calibration (0047,
`Calibration/README.md`: masters, library index, matching). Card 0048 (pipeline) ports against
the same oracles.

**StarNet** (card 0055, `StarNet/`): `StarNetRunner.located(by: HostTools)` → `.missing` (no
binary) or `.cannotRun` (`ExecutableCheck`: an x86_64 build without Rosetta) as
`StarNetError`, never a fallback. `HostTools.live` already reports such a StarNet as
`ToolStatus.cannotRun(path:reason:)` (`Probe.refusal`), so every screen says « installed but
cannot run », never « missing » (card 0108); `starless(of:in:onProgress:)` writes a 16-bit TIFF, runs it,
reads the TIFF back (`ImageImport`). `StarNetCLI` probes `--machine-info` for the StarNet2 flag
CLI (`-i/-o`) vs StarNet++ positional; `StarNetProgress` reads every `N.N%` in the unbroken
`Working: 8.3%Working: 16.7%…` stream. No starless cache yet (legacy `starlessTIFF` reuse).

**Background extraction** (card 0072, `Background/` + `GraXpert/`): the engine behind the
Studio's process (0092 is the panel). `BackgroundExtraction(graxpert:siril:)` — or
`.located(by: HostTools, siril:)` — runs `run(image:engine:correction:scratch:onProgress:)` and
returns `BackgroundResult` (`corrected`, `model`, `reused`): the model is `input − corrected`
(subtract) or `input ÷ corrected` (divide), computed in ImageKit so every engine returns the same
pair. Engines (`BackgroundEngine`): `.graxpert(smoothing:)` through `GraXpertRunner`
(`GRAXPERT_APP`, else `/Applications/GraXpert.app`; `<file> -cli -cmd background-extraction
-output … -correction … -smoothing …`; a missing app is `GraXpertError.missing`, never a Siril
engine instead — R2; a run past `timeout` is torn down), `.sirilRBF(…)` and
`.sirilPolynomial(degree:)` through `SirilScripts.backgroundExtraction` (`load` → `subsky` →
`save`; `SirilCommand.subskyRBF` carries the legacy `SubskyRBFCmd` flags). The Siril engines only
subtract (`unsupportedCorrection`); every value is validated against the tool's range
(`outOfRange`), never clamped. `BackgroundCache` under `<scratch>/background/<sha256>/` keys the
pair on the input pixels + engine + correction: the same request again makes no tool call.
Progress lines of both tools arrive as `ToolProgress` (`ProgressPercent`: the legacy `N%` rule);
Siril's script mode and GraXpert run through one `ToolProcess.runLines` (swift-subprocess,
teardown on cancellation, `LineSplitter`). Every `siril-cli` launch (pipe, script,
`--version`) runs with `SirilTool.englishLocale` over the app's environment, and the app's `-i`
settings carry `lang=en_US`: every log reader (plate solve, SPCC, error hints) matches English
sentences (card 0124), so a reader is never translated. Launches without `-i` (pipe, masters,
background) still follow a language picked in the user's own Siril settings. GraXpert 3.0 appends the input's
extension to `-output` (the stem is passed) and logs a fatal AI failure as `Critical error` while exiting 0
(`GraXpertError.reportedError`, the legacy `firstErrorLine`).

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

## Knobs (card 0070)

- `KnobSchema.knobs` is every `PreprocessSettings` value a user may move, once:
  - its wire id (the legacy `params_patch.go` key when there was one);
  - its kind (number with bounds and integer flag, flag, or choice ids);
  - its level (simple or advanced);
  - its scope (card 0121): `.lane` when one lane's stacker reads it alone (stack options,
    grading, transient mask, wheel transition), `.run(Shared)` when the shared canvas reads it,
    with why (registration, framing, nights, combine; the frame-review and reference
    breakpoints too, toggled once for the run on the Tri stage, which shows them run-wide).
- **Lane overrides (card 0121, every clip filter since 0134):**
  `PreprocessRequest.overrideLane(_:with:)` sets a lane kind's (`FilterSet`: broadband, or a line
  clip — dual-band, SII+OIII, multi-band) lane-scoped patch, refusing a run-wide knob
  (`KnobError.runWide`); `settings(forLane:in:)` resolves it through `FilterSetLanes.laneKind(of:)`
  in `stackChannel` and in the lane's checkpoint digest — only in a split run (a line-clip lane
  exists), so an unsplit run never applies an override. Lanes: a line clip's lane is
  `<filter>-<set.rawValue>` (`RGB-dualband` unchanged), `FilterSetLanes.lineLanes(in:)` lists them
  in `FilterSet` order, the aligner registers them last onto the broadband grid, and
  `DualbandSplit.channels` writes each lane's lines (`FilterSet.lines`) as `syn_<line>` — a line two
  lanes carry is kept from the first and noted. Two line clips without a broadband set split too —
  never one master: the first lane (`FilterSet` order) is the colour base, the others' lines go over
  it, and no continuum scale is fitted (no broadband reference). They live on the request, not in
  `PreprocessSettings`: an untouched run's settings, scripts and `LaneRecord` digests are byte-
  identical.
- `KnobSchema.apply(_:to:)` puts a `KnobPatch` on the preset. An unknown id or a refused value
  throws before anything is applied. `patch(from:mode:)` returns only what differs from the
  preset, so a patch of defaults is a no-op and untouched runs stay byte-identical.
- `Tests/StackKitTests/Fixtures/knobs/legacy-deepsky-knobs.json` accounts for every legacy
  deepsky key: preprocessing, finishing (ProcessKit), or not ported (with the reason).
- **To add a knob:** expose the value in `PreprocessSettings`, add it to `KnobSchema+Knobs.swift`
  under its area, list it in the fixture (`preprocess` or `swiftOnly`), and give it its words in
  HelpKit's `Help/<locale>/knobs.json` (`knob.<id>`, plus `knob.<id>.<option>` for a choice).
  Give it its scope: `.shared(_:)` in the schema when the shared canvas reads it (the app words
  the reason), its row in `KnobSchemaTests+Scope.swift` either way.
  `KnobSchemaTests` and `KnobPanelViewModelTests` fail on any one missing.
**Sky-object catalogue** (card 0129, `Astrometry/SkyCatalogue*.swift`, port of the legacy
`internal/skycat`): `SkyCatalogue.installed()` reads the five lists the installed Siril ships
(`folder(sirilPath:)`: `…/Siril.app/Contents/Resources/share/siril/catalogue`, or the prefix's
`share/siril/catalogue` beside a `bin/siril-cli`; `SIRIL_BIN` honoured; no Siril →
`SkyCatalogueError.sirilMissing`, the app's install card) and merges them Messier → NGC → IC → Sh2 →
LDN: the first list wins the primary name, later ones fill missing photometry and add their names as
aliases. `object(named:)` finds any name or alias; `search(_:limit:)` ranks exact → prefix →
contains, name → common name → alias, then the list, then the brighter. `SkyCatalogue.normalize` is
**the** object-name key (A–Z, 0–9, upper-cased): compare a FITS `OBJECT` with it, never with a
second normaliser. The OpenNGC overlay (`Resources/Catalogue/openngc.csv`, CC-BY-SA-4.0, attribution
in its README) adds types, ellipses, surface brightness, morphology and common names by name, never
coordinates. Siril's CSVs are never copied into the repo (one list). To extend: a new Siril list is a
`SkyObject.Source` case in load order (its rank in search follows); a new overlay column is an
`OverlayEntry` field.

**Plate solving** (card 0093, `Astrometry/`): `PlateSolver(siril:support:catalogues:)` — or
`.live(binary:support:catalogues:)`, a `SirilRunner.live(…, initFile:)` passing `-i` — runs
`load input` → `platesolve <ra,dec> -force -focal= -pixelsize= [-limitmag=] -catalog= -noflip` →
`save solved` (`SirilCommand.platesolveForced`; Siril 1.4.4 refuses the coordinates after
`-force`) on the image as is, and returns `Solved {solution, wcs}`: the `PlateSolution` read from
Siril's lines (centre, ″/px, rotation, focal, pixel size, field, catalogue, offset) and the `WCS`
of the file Siril wrote — the pixels stay the caller's (`-noflip`). Siril runs on the app's own
settings file (`<support>/siril-platesolve.ini`, rewritten before each run: the local Gaia paths
under `catalogues`, `update_default_scale=false`), never on the user's, which a plain
`platesolve` rewrites and whose stale catalogue paths made Siril go online silently
(`docs/design/validation-e17.md`). Local Gaia without `siril_cat_healpix8_astro.dat` is
`PlateSolveError.catalogueMissing` before Siril runs; no solution is `.failed(reason:)` with
Siril's `Plate solving failed: …` line, never retried with other settings. A run that ends
without a solution says which part is missing: `.noReport` (no centre, scale or rotation in the
log; the last lines `platesolve` printed), `.reportUnread` (Siril said it solved; this reader
missed its lines), `.noFile`, `.unreadableFile`, `.noSolution` (a file without a readable TAN
solution) — each naming the kept log. Siril's whole output of the last solve is kept in
`<support>/siril-platesolve.log`, and that of the last failed one in
`<support>/siril-platesolve.failed.log`, which a successful retry keeps. Transcripts recorded
on run #78's crop are in `Tests/StackKitTests/Fixtures/platesolve/` (0.6 s wall live).

**Colour calibration** (card 0094, `Colour/`): `ColourCalibrator(siril:support:catalogues:)` —
or `.live(…)` with `-i` on `<support>/siril-colour.ini` (`SirilAppSettings`, shared with the plate
solver) — runs `load input` → `spcc "-oscsensor=…" "-oscfilter=…" "-whiteref=…" -bgtol=below,above
-catalog=…` or `pcc …` → `save calibrated` on a solved image (`.unsolved` otherwise; the input
FITS carries the image's WCS). SPCC names are first checked against `spcc_list` (Siril 1.4.4
runs an unknown sensor as the previous one: `.unknownName`); `-bgtol` takes both tolerances as
magnitudes (a negative lower one is refused, despite Siril's help). `ColourCalibrationReport`
reads the applied factors (last `K0…K2`), stars used, background and Siril's « imprecise
solution » warning; a failure is `.failed(reason:)` with the line before Siril's locator — never
another method. Transcripts in `Tests/StackKitTests/Fixtures/colourcal/` (0.7 s wall live).

## Run scope (card 0095)

`Preprocess/RunScope.swift`: `RunScope(object:setIDs:lights:listed:)` names the light sets one run
stacks, among those the scan `listed` for the object when they were chosen;
`RunScope.scopes(of:)` gives one per object of a scan, `Inventory.scoped(_:)` keeps those light
sets and every calibration set with the ids the scan gave (unlike `subset`, which regroups), and
`Preprocessor.plan` refuses lights of several objects (`PreprocessError.mixedObjects`, an empty
OBJECT being an object of its own) or none (`noLights`) — one object per run, never the legacy
« dominant object ». `RunScope.unlistedSets(in:)` names the sets of the object a re-planned scan
holds beyond what was listed, or chosen sets it lists no more (the app refuses the run with
`scopeOutdated`); a set listed and left unchecked is a choice, not a change. A scoped inventory
takes the colour model of the lights it keeps: a mixed scan names its colour lights `RGB`
(`nameColorChannel`), so a mono object beside an OSC one stacks as two runs, while one object shot
by both rigs is still refused as mixed. The app queues one run per checked object.

## Scratch owners and the leftover sweep (card 0113)

Every scratch folder the app or a test creates carries `owner.json` (`ScratchOwner`): the pid and
start time of the process that made it, and the Siril it launched there. Today: Siril's FIFO
folders (`$TMPDIR/AstroStack/siril-*`, `SirilPipeInstance`), each run's work folder
(`Preprocessor.perform` marks `request.work`), an untitled project's folder
(`AstroStack/Untitled/<UUID>/`, the marker beside the package, never in it) and each test's
scratch folder (`TestSupport/ScratchDirectory`, the marker one level above the test's directory).

`LeftoverSweep` runs at app launch (`AppDelegate.sweepLeftovers`); a test process sweeps only the
tests' own `AstroStackTests` folder (`ScratchDirectory`), never the app's. Per
root it takes only the folders with the root's prefix **and a marker** whose owner no longer runs
(after stopping its recorded Siril, only while that pid still runs the program recorded at
launch, started when recorded; a Siril left running keeps its folder). Markers are best effort: a
folder that could not be marked is never swept, never a run that cannot start. An unmarked entry, a file or a symbolic link is
never taken, whatever its age: nothing proves the app made it (24/10: an age rule run on a wrong
root deleted most of /opt/homebrew). A root that is `/`, inside or around `~/Documents/astro` is
refused (R7); tests check that with `allows`, never by sweeping a real path. `ProcessTable` is the
only door to the process table; tests pass a fake one.

Stack folders (`StackLeftovers`): a failed or cancelled run's `stacks/<id>/` goes unless it holds a
finished `master_*.fits`; at project open and when a queue ends, folders no stack row names are
removed when empty (the Finder's `.DS_Store` counts as empty) and listed in the Stacking stage
otherwise, deleted only by the user (R2); a folder a run still holds (`TargetLock`) or a paused
run's checkpoint (card 0097) is neither.

To add a scratch folder: create it, `ScratchOwner.mark` it, and give its parent a `Root` in
`LeftoverSweep.appRoots` with a prefix that names only such folders.

## How to extend

- A port loads its case with `OracleCase.load` and compares: bytes for scripts and Siril masters,
  `meanAbs`/`maxAbs`/PSNR with a written tolerance for anything numeric (testing-conventions.md).
- Live cases go in `Live…` suites with `.liveFixtures`, `.tags(.live)`; find them with
  `OracleLiveCases.find` (tests).
- Host tools run through swift-subprocess; a missing tool is a typed error, never a fallback (R2).
- Allowed dependencies: `ImageKit`, `ProjectKit` (`Tests/TestSupport/BoundaryRules.swift`).
