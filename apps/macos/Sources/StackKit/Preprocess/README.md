# StackKit / Preprocess

One night, from captures to a linear bundle (card 0048): port of the single-night deep-sky path of
the legacy `internal/pipeline` + `internal/grade`, pinned by 0044 case (a). In CI,
`PreprocessOracleTests` replays Siril and checks the 18 scripts byte for byte and in order, the
selection, the setrefs and the warnings. Live, `PreprocessLiveTests` runs the host Siril in
script **and** pipe mode and gets byte-identical masters, aligned channels and trims.

## Steps (`Preprocessor`, an actor; events on an `AsyncThrowingStream`)

| # | Step title | Type | Legacy |
|---|---|---|---|
| 1 | building master calibration frames | `MasterBuilder` (0047) | `BuildMasters` |
| 2… | grading + stacking `<object> <filter>` (one per light set, canonical filter order) | `ChannelStacker` → `ChannelGrading` → `Grader` | `processChannel`, `finishStackedChannel`, `gradeChannel`, `stackSelectedOrCopy`, `finishLinearMaster` (BAYERPAT strip) |
| n+1 | aligning channels | `ChannelAligner` (+ `ParityNormalizer`), then `EdgeCropper` (`EdgeTrim`) | `alignChannels`, `normalizeMasterParity`, `retryPairAlign`, `applyAlignPolicy`, `applyEdgeCrop`, `measureEdgeTrim` |
| n+2 | combining channels (Siril) | `ChannelCombiner` | `buildCombine` + `NeutralizeScript` |
| n+3 | writing the linear bundle | `BundleWriter` | new (E04 design) |

Each step emits `.progress(step, steps, title, percent, line)` and each master and the composite
emit `.preview(stage, pngPath)` (`PreviewRenderer`: an asinh display stretch, display only). The
last event is `.finished(PreprocessResult)`. Cancelling the consuming task stops the run between
Siril commands. Finished masters stay, and the bundle, written last, never appears. A second run
on the same output folder throws `targetBusy` (`TargetLock`). Multi-night captures
(`multiNight`, card 0066) and mono + colour mixes (`mixedColorModel`) are refused before
anything runs.

Layout, as the legacy engine had it: `work/` holds `masters/`, `light_<lane>/` (removed once
stacked), `04_aligned/` and `pair_<lane>/`. `output/` holds `master_<tag>.fits`,
`aligned_<tag>.fits`, `trim_<tag>.fits`, `combined.fits`, the `*_preview.png` files and
`bundle.json`.

## The bundle (`LinearBundle`, `bundle.json`)

```
{version: 1, run_id, color_model: mono|osc, grid: {width, height},
 layers: [{id: <filter>, role: lum|red|green|blue|rgb|line, file: trim_L.fits,
           source: trim|aligned|master, stats: {bg, madn, sky, snr}, continuum_k?}]}
```

Layers are the combine inputs (trim > aligned > master), in canonical filter order, and
mixed dimensions are refused with no file written. The stats are measured on every pixel with
the planes averaged:

- `bg` is the median;
- `madn` is 1.4826 · the MAD from `bg`;
- `sky` is the median of the pixels ≤ `bg + 3·madn`;
- `snr` is `bg / madn`.

`continuum_k` is set by the multi-night Hα continuum (0066). 0043 builds the same type from a
legacy run.

## Several nights (card 0066)

`NightPlan` groups each channel's light sets per night. When one channel has two or more,
the run is anchored: the anchor night covers the most channels, then has the most frames, then
is the latest. Every channel then takes `GroupedChannelStacker` (`processChannelGroups`), a
one-night channel included, so all masters land on the anchor night's canvas.

1. **Per night:** link, then `calibrate` with the night's own masters (`calibrate_single` for a
   lone frame); strip BAYERPAT; check parity with `ParityCache`. One no-flip solve per session,
   seeded by `solveCoordinates` (filled from the lights' OBJCTRA/OBJCTDEC when the request
   carries none); a mirrored session is flipped and the flip verified.
2. **Photometry** (`StackKit/Photometry`, `photom`): each night is fitted onto the anchor night's
   14-percentile curve (Theil–Sen), the no-clip gate is applied, and the frames are rewritten
   `scale · p + offset`.
3. **Merge:** `merged_<lane>` links every night's frames. A per-frame flatten (`seqsubsky 1`) is
   followed by a two-pass homography registration. If the flatten fails, the folder is put back
   to its links before a plain registration. The legacy engine re-linked the dirty folder and
   stacked every frame twice (fixed, PO 2026-10-20).
4. **Review** (`RegistrationReview`): the anchor night's middle frame is pinned (`setref`); a
   transform overlapping the anchor field under 20% is a false star match and pre-rejected;
   each night's rotation and overlap are recorded.
5. **Seam offsets** (`SeamOffsetRefit`): each night's pedestal is re-measured against the
   anchor's inside their shared footprint. The guarded Δ is added before `seqapplyreg`.
6. `seqapplyreg -framing=current`, then grading per night (spans).
7. **Saturated cores** (`SaturationRepair`): sensor-clipped pixels are replaced by the median of
   the nights that still see them below their own ceiling (at least five). This is an exact
   sparse pass, never the whole sequence in memory.
8. Stack (weight `noise` when a night was rescaled beyond ×4). **Coverage** (`CoverageGrid`,
   8-px cells) is computed, then the **seam noise** pass (`SeamNoiseEqualiser`, `StackKit/Noise`):
   a weighted starlet denoise of strength √(depth_max/depth) − 1. The full-depth core stays byte
   for byte; a colour master is denoised in luminance only.
9. **At the combine:** `CoverageCrop` cuts the inputs to the field every channel covers
   (`combine_<tag>`), before the edge trim.

Calibration masters also get their dark **defect map** (`DarkDefects`, `<dark>_defects.lst`,
applied with `-cc=bpm`).

**Pins.** Case (b) in CI: scripts, selection, nights and setrefs, as recorded with the
duplicate-frame fix. Case (b) live: calibration masters, G and B byte-identical; photometry and
geometry within 1e-9 of `run.json`; the seam records, including the coverage-only `weight_max`,
bit for bit. L and R are held to mean |Δ| ≤ 1e-3 of the recorded range, since they legitimately
differ by the fix. Case (d) live: calibration masters by hash; records; the master within the
same bound. The float ports (photometry apply, starlet, bilinear weights) fuse products where
arm64 Go does.

## Rules worth knowing

- R2: every decision is visible. A rejected frame carries its reason; a restored one says
  `kept (stack minimum) — was: …`. Parity flips, alignment fallbacks, a capped edge trim and a
  failed channel are all warnings, never silent.
- A failed channel is an outcome with an `error`, and the run continues without it. Only
  cancellation, the lock and the up-front refusals end a run.
- Tests substitute `Preprocessor.Tools`: Siril (`PipelineSiril` plays its file side), the trail
  probe and the edge measurement, which are the only decisions read from pixels.
- `SirilMode.default` is `.pipe`; `SirilRunner.make(mode:binary:work:)` builds either mode. A
  pipe session runs each script as one unit (`SirilSession.execScript`), and the pair rescue
  ends with `setfindstar reset` because the session outlives the script that relaxed it.
- Settings come from `PreprocessSettings.preset(mode)` (deepsky, or nebula: lenient grading and a
  degree-2 sky) unless the request carries its own. `solveCoordinates` feeds the parity
  probes' `platesolve`. Stacked masters lose their pointing cards, so without it they rarely
  solve, and the run says the parity check was skipped. Filling it from the target is the
  import view's job (0056).
- Every sequence folder (`light_<lane>`, `04_aligned`, `pair_<lane>`) is emptied before
  `link`, because Siril takes every FITS it finds there.

## Not ported here (and why)

- The legacy finish (autostretch, GIMP, exports: scripts 0019–0022) belongs to the Studio (E12).
  Highlight headroom is a stretch-time step on copies, so it never touches the linear layers.
- The cross-frame transient trail mask (k > 0), the broadband/dual-band lanes with the
  `syn_Ha`/`syn_OIII` split and `continuum_k`: a follow-up card (PO 2026-10-20). No recorded
  oracle exercises them; the trail mask stays off until then.
- The mosaic union canvas (`Mosaic`) is not ported.
- AI background, linear denoise, the cosmetic repair of never-dark-calibrated masters and the
  dither report are off or no-ops in the deep-sky golden. They come back as Studio processes or
  with the frame review (0069–0071).
- The Go native combiner (`stacknative`) is not ported unless 0058 finds a profile that needs it.

## Extending

A new step is a type taking the run's `SirilRunner` and a `PreprocessJournal`, called from
`Preprocessor+Steps.swift` with an `emitter.begin(title)`. Add its scripts to `SirilScripts`
(with a sample in `SirilCommand+Samples` for a new verb). Pin it with the oracle replay: extend
`PipelineSiril` for the files its scripts produce.
