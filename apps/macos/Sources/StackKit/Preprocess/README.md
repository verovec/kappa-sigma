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
| 2… | grading + stacking `<object> <lane>` (one per lane, canonical filter order) | `ChannelStacker` → `ChannelGrading` → `Grader`, then `maskRegistered` (`SaturationRepair`, `ChannelTrailMask`) | `processChannel`, `finishStackedChannel`, `gradeChannel`, `applyTrailMask`, `stackSelectedOrCopy`, `finishLinearMaster` (BAYERPAT strip) |
| n+1 | aligning channels | `ChannelAligner` (+ `ParityNormalizer`), `CoverageCrop`, `EdgeCropper` (`EdgeTrim`), then `emission` (`DualbandSplit`, `ContinuumK`) | `alignChannels`, `normalizeMasterParity`, `retryPairAlign`, `applyAlignPolicy`, `applyEdgeCrop`, `measureEdgeTrim`, `dualSetChannels`, `lineContinuumSubtract` (k only) |
| n+2 | combining channels (Siril) | `ChannelCombiner` | `buildCombine` + `NeutralizeScript` |
| n+3 | writing the linear bundle | `BundleWriter` | new (E04 design) |

Each step emits `.progress(step, steps, title, percent, line)` and each master and the composite
emit `.preview(stage, pngPath)` (`PreviewRenderer`: an asinh display stretch, display only). The
last event is `.finished(PreprocessResult)`. Cancelling the consuming task stops the run between
Siril commands. Finished masters stay, and the bundle, written last, never appears. A second run
on the same output folder throws `targetBusy` (`TargetLock`). Mono + colour mixes
(`mixedColorModel`) are refused before anything runs.

The app consumes the stream in `RunViewModel` (card 0057, Stacking stage). Each step becomes a row
(pending → running → done, failed or cancelled), the last percentage of the current step is a bar,
previews form a strip that replaces by stage, and every non-empty `line` goes into a filterable
journal. Its `RunServices.live` runs `Preprocessor` over `SirilRunner.make(mode: .default…)` into
the project's `stacks/<run_id>/`, with `work/` in a temporary `run_<id>` folder that is removed
when the run ends. `Progress` and `Preview` have package inits, so app tests can replay a
recorded stream.

**Scratch budget (card 0098).** `ScratchEstimate(inventory, settings:)` is the peak the work
folder reaches: lanes run one after another and each removes its folders, so the largest lane
sets it, at one 32-bit copy of each light per Siril step that writes one (`pp_`, `r_`, plus
`flat_` when a multi-night lane flattens), colour lights debayered (three planes). It is pinned
against 0058's measured peaks (M 31 80.6 GB, IC 1848 106 GB) within 10 %. A Siril step that
writes another per-frame copy must add it here, with its test row. `ScratchSpace.available(at:)`
reads the room left on the scratch volume. The app checks both before Siril starts
(`check(room:folder:)` throws `scratchFull`) and shows them on the Stacking stage. The scratch
folder is the Settings choice (`ScratchSetting`, always an app-owned `AstroStack/Work` subfolder),
read by `RunServices` at each run.

Layout, as the legacy engine had it: `work/` holds `masters/`, `light_<lane>/` (removed once
stacked), `04_aligned/` and `pair_<lane>/`. `output/` holds `master_<tag>.fits`,
`aligned_<tag>.fits`, `trim_<tag>.fits`, a split capture's `syn_Ha.fits` / `syn_OIII.fits`,
`combined.fits`, the `*_preview.png` files and `bundle.json`.

## Lanes and emission layers (card 0081)

A one-shot-colour scan holding BOTH a measured broadband and a measured dual-band light set
(`FilterSetLanes.splits`) stacks two lanes: `RGB` and `RGB-dualband`. The lane renames the
stack, never the light, so calibration still matches on the real key. One verdict alone, or an
unclassified set, keeps the single lane (a dual-band-only capture is not split). At the
alignment the broadband master leads and is pinned as the reference
(`SirilScripts.alignMastersReference`: one pass, `-2pass` would override the pin), then, after
the crops, the registered dual-band master is separated (`DualbandSplit`): `syn_Ha` = red,
`syn_OIII` = max(green, blue). The lane leaves the channel map; with no broadband master left it
is the colour channel itself, unsplit. The composite is built from the colour base alone.

Every emission layer then gets its continuum scale `continuum_k` (`ContinuumK`: the median
line/ref ratio over the P85–P99.9 reference pixels): Hα and [SII] against R then L, [OIII] against
G, B then L, and past those a colour base's red (or green) plane — which the legacy list lacked.
Each split and each scale (or why there is none) is a `PreprocessResult.notes` line. The palette-
gated split of a dual-band-only capture (`duobandChannels`) and the excess layer itself are the
Studio's (0051).

## The cross-frame trail mask (card 0081)

After grading, every registered frame goes through `ChannelStacker.maskRegistered`: the saturated
cores first (multi-night), then the trail mask at `PreprocessSettings.trailMaskK` (deepsky and
nebula 3.0, 0 = off), in memory or streamed under the memory budget
(`Transient/README.md`). What it cleaned is `ChannelOutcome.trailMask` and one note in the legacy
wording; a failure is a note and the frames stack as they are. The 0044 cases were recorded with
the mask off: their tests run `PreprocessSettings.recorded` (k = 0).

## The frame review breakpoint (card 0069)

With `PreprocessSettings.frameReview` on (knob `frame_review`, simple, default off), every lane
pauses right after `ChannelGrading.grade`, single night and merged nights alike: the stacker's
`frameReview` hook gets a `FrameReviewContext` (grades as graded, spans, nights, the `.seq`
reference as `FrameGrade.index`, the registered frame of each grade) and must return a
`FrameDecision` (`exclude`, `forceKeep`, by `FrameGrade.index`). `ChannelGrading.apply` puts the
decision on the grades before the `unselect` mapping: an excluded frame is rejected with reason
`user` (`user — was: <the grader's wording>` when the grader had restored it for the stack
minimum), a force-kept one is restored as `kept (user) — was: <the grader's reason>`; an
unregistered frame cannot be kept. Nothing restores a frame the user excluded (R2): under Siril's
two-frame minimum the lane fails with `belowStackMinimum`, and the Tri pane greys Continue first. The `Preprocessor` installs the hook itself: it renders a
quick look per registered frame under `work/frames/<lane>/NNNNN.png` (`tools.preview`), emits
`PreprocessEvent.frames(…)` carrying a `FrameReviewGate`, journals that it waits, and awaits
`gate.resume(_:)` from whoever consumes the stream (the app's `RunViewModel`). Cancelling the run
releases the gate with `CancellationError`; a late answer is ignored. Off, no event, no hook, and
the scripts are the recorded ones byte for byte (`PreprocessorFrameReviewTests`).

Every run writes `grades.json` (`GradesRecord`) beside the bundle once the lanes are stacked:
per lane the grades as stacked, the nights, the reference, whether it was reviewed and the
decision — the Tri stage reads it back after the work folder is gone. The stack's record in the
app (`StackRecord.frameReview`) keeps the decisions per lane too.

## The registration reference pin (card 0096)

With `PreprocessSettings.referenceBreakpoint` on (knob `reference_breakpoint`, advanced, default
off), every lane pauses once Siril has measured its frames and before the registration is
applied: the stacker's `referencePin` hook gets a `ReferencePinContext` (the frames as measured,
never graded; each frame's night and parity; the elected reference as `FrameGrade.index`) and
returns a pin, or nil to keep the election. The `Preprocessor` installs the hook and emits
`PreprocessEvent.reference(…)` with a `ReferencePinGate` (a `ReviewGate<Int?>`, the same type
the frame review uses with a `FrameDecision`).

- Several nights (`GroupedChannelStacker+Merge`): the pause sits after `register -2pass` and
  before `RegistrationReview`, whose `pinned:` replaces the anchor night's middle frame as the
  reference the overlap pre-rejects, the seam refit, `setref` + `seqapplyreg` and the coverage
  homographies are computed against. A pin on a dropped frame is a warning; the election stands.
  A pin on another night moves that lane's canvas and orientation to the pinned frame's field
  (the « every lane on the anchor night's canvas » rule of 0066 holds without a pin); the
  election shown is the anchor night's middle registered frame, else Siril's own reference.
  Only frames registered with a transform are candidates (`RegistrationReview.registered`), on
  every path and in the Tri pane alike.
- One night (`ChannelStacker.calibrateRegister`): the election is Siril's own (`S` line, else
  frame 1). With two-pass registration the pin rides `applyRegistration(reference:)`; one-pass,
  a pin that differs runs `SirilScripts.pinReference` (`setref` + `register` once more).

No pin, or the elected frame, leaves the recorded scripts byte for byte
(`PreprocessorReferencePinTests`). The pin is `ChannelOutcome.referencePin`, in `grades.json` as
`pinned_reference`, and in the app's stack record as `reference_pins`.

## The bundle (`LinearBundle`, `bundle.json`)

```
{version: 1, run_id, color_model: mono|osc, grid: {width, height},
 layers: [{id: <filter>, role: lum|red|green|blue|rgb|line, file: trim_L.fits,
           source: trim|aligned|master|syn, stats: {bg, madn, sky, snr}, continuum_k?, continuum_ref?}]}
```

Layers are the combine inputs (trim > aligned > master), in canonical filter order, and
mixed dimensions are refused with no file written. The stats are measured on every pixel with
the planes averaged:

- `bg` is the median;
- `madn` is 1.4826 · the MAD from `bg`;
- `sky` is the median of the pixels ≤ `bg + 3·madn`;
- `snr` is `bg / madn`.

`continuum_k` is a line layer's continuum scale (`ContinuumK`, card 0081) and `continuum_ref` the plane it was fitted against (`R`, `RGB.r`…, card 0051: what the Studio subtracts); `source` is `syn` for
a layer separated from a colour master. 0043 builds the same type from a
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
