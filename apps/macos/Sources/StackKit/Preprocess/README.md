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
- Multi-night groups, lanes, seams, photometry and the transient mask: 0066. The dual-band lane
  split: with 0066's lanes.
- AI background, linear denoise, the cosmetic repair of never-dark-calibrated masters and the
  dither report are off or no-ops in the deep-sky golden. They come back as Studio processes or
  with the frame review (0069–0071).
- The Go native combiner (`stacknative`) is not ported unless 0058 finds a profile that needs it.

## Extending

A new step is a type taking the run's `SirilRunner` and a `PreprocessJournal`, called from
`Preprocessor+Steps.swift` with an `emitter.begin(title)`. Add its scripts to `SirilScripts`
(with a sample in `SirilCommand+Samples` for a new verb). Pin it with the oracle replay: extend
`PipelineSiril` for the files its scripts produce.
