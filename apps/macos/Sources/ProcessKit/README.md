# ProcessKit

The Studio's process seam: parameter schemas, the GPU render shared by preview and Apply, the
non-destructive history, recipes and the registry (design §2, §4.1).

## What exists (card 0049)

- `ImageProcess` (named so to avoid `Foundation.Process`): `id`, `title`, `stage`
  (linear/nonlinear/any), `requires: [LayerRole]`, `schema`, `previewExactOnlyAt1to1`,
  `render(_:stats:into:context:)`, `suggestions(stats:)`. R2: `render` reads the image, the
  bundle `LayerStats` and `params`, never measures the image to set itself; measurements return
  as `Suggestion`s.
- `ParamSchema` / `ParamSpec` (number with bounds, flag, choice, curve `points` (card 0053: 2 to
  `maxCount` `CurvePoint`s, clamped into [0, 1], sorted, one per x; JSON `[[x, y], …]`); `ParamUnit` none/px/sigma/opacity;
  `ParamLevel` simple/advanced with the display rule `visible(disclosed:promoted:)`), `ParamSet`
  (schema order, clamped, NaN refused, encoded as ordered JSON; no decoder: stored values come
  back through `ParamSet.loading`, which validates them and returns what it refused).
- `GPUImage` (r32Float planes, read/write, shared), `ProcessRunner` (synchronous run),
  `ProcessLibrary` (pipelines with RenderKit's fast-math-off compile options).
- `ProcessContracts`: **PreviewEqualsApply**, **NoHiddenState**, **PxUnitsScale** (a `.px` value
  `v` at scale 2 = `v / 2` at scale 1, every other `.px` value halved with it), bit-exact.
- `History` (one folder per image): steps (process, params, output FITS via `FITSFile.create`,
  numbered after what the folder already holds), undo/redo reloading from disk (atomic), named
  `snapshots` that survive undo (the viewer's compare reference), `save()` removes only the
  unreferenced outputs it wrote, `diskBytes` for the project budget (0068); images handed in or
  out are copies.
- `Recipe` (format v1): JSON export; import clamps values, and unknown keys or parameters are
  warnings while an unknown process or a newer format is an error.
- **ChannelCombinationProcess** (card 0054), the first node of every pipeline: slots R/G/B/L ← bundle
  layer planes (`RenderContext.layers`: `RGB`, `R`, `G`, `B`, `L`, `Ha`, `OIII`, `SII`),
  `w·max(x − black, 0)` per slot, Foraxx's green = √(Hα·OIII), L replaces the luminance at its
  opacity. `Palette` (natural, HOO, SHO, HOS, Foraxx, LRGB) fills the source slots only. A
  missing layer gives `unavailableReason` ("HOO needs an OIII layer") and `ProcessError.missingLayer`
  — never another layer (R2).
- **Masks** (card 0054): `Mask` = `MaskSource` (luminosity range with linear soft edges; stars
  proxy = luma above its local mean, until 0055's star layer) + feather (box blur of
  `round(px / scale)`: a hard edge becomes a linear ramp) + invert, built by `MaskBuilder`.
  `ProcessRunner.run(…, mask:)` blends `m·processed + (1 − m)·input` — no process masks itself, and
  `ProcessContracts` runs every process under a half mask too.
- **StretchProcess** (card 0050), the first non-linear step, one kernel (`Stretch.metal`) with
  three modes after an optional headroom cap (legacy `CompressHighlights`: tanh shoulder on the
  0.299/0.587/0.114 luminance, every channel scaled alike):
  - `mtf`: Siril's autostretch from the bundle `LayerStats` — c0 = median + clip·MADN, m =
    MTF(target, median − c0), linked = mean median and MADN — with RenderKit's `MTF`;
  - `ghs`: the Generalised Hyperbolic Stretch equations (`GHS`; ln(D+1), b, SP, LP ≤ SP ≤ HP,
    D = 0 is the identity);
  - `asinh`: ratio-preserving above a black point.

  Every coefficient is computed on the CPU (`StretchUniforms`) from the panel values and the
  stats; "autostretch like Siril" and the deep-sky 0.90 headroom are suggestions, not defaults
  hidden in the shader. The Studio panel draws its MTF black point and midtone as handles on the
  head's histogram (`HistogramHandled`): a drag sets `shadowsClip` and `targetBackground` through
  RenderKit's `STFMapping`, as the viewer's σ controls read them.
- **LevelsProcess** (card 0089, id `levels`, « Histogram transformation »): PixInsight's
  HistogramTransformation / Siril `mtf low mid high`. A black point, a midtone balance and a white
  point for RGB/K (`rgbShadows`, `rgbMidtones`, `rgbHighlights`), one triple per channel when
  `linked` is off (`r…`, `g…`, `b…`, promoted out of the disclosure then), applied before the
  RGB/K one, then the output range (`outputLow`, `outputHigh`). An identity triple is skipped, so
  the defaults return the input bit for bit; c1 ≤ c0 is refused with the reason. Suggestions:
  Siril's autostretch (−2.8σ, 0.25) and, added by the app, the viewer's display stretch (the
  STF → HT handoff); several values of one reason are taken together. Pinned bit for bit against
  a float mirror of `stf` (`LevelsProcessTests`) and against Siril `mtf` (mean |Δ| ≤ 1/65535,
  `LiveSirilMTFParityTests`).
- **One MTF.** `Stretch.metal`, `Screens.metal` and `Levels.metal` `#include "STF.h"`, RenderKit's
  header of the display stretch, which `ProcessLibrary` inlines at compile time (the runtime
  compiler has no include path). Its denominator is an explicit `fma`, so a float oracle mirrors
  it exactly.
- **EmissionScreensProcess** (card 0051, id `emission-screens`): astrocomp's HOO-over-broadband
  chain on a stretched RGB base. Per line (`EmissionLine`: Hα, [OIII], [SII]; params
  `<ha|oiii|sii><Enabled|Continuum|ContinuumK|Background|Black|Opacity|Tint|Boost>`) on its own
  linear bundle layer: continuum `max(line − k·ref, 0)` (k = the panel value; the bundle's
  `continuum_k` is a suggestion, the reference plane is the bundle's `continuum_ref`), the
  astrocomp MTF (`LineStretch`: x₀ normalised by 1 − c, NOT the Siril form of `stretch`), black
  point, tanh boost (knee 0.60, ceiling 0.98), grey opening (`starRadius` px), 3-box smoothing
  (`smooth` px), then `base + α·line·tint·(1 − base)` in line order (α = opacity · `nbBlend`).
  After a continuum subtraction the stretch stats are derived (median − k·ref median, MADNs in
  quadrature), never measured. The black point reads in σ of the stretched bundle noise
  (`blackInSigma`); suggestions: k, black = 3σ. Global `linkLayers` = astrocomp `-link-layers`.
- `LayerPlane` (`R` / `RGB.r` tokens → texture + per-plane stats). `RenderContext.layerStats`
  (and `ProcessRunner.run(layerStats:)`, `ProcessContracts(layerStats:)`) hand a process the
  bundle statistics of every layer it reads; `LayerStats.continuumK/continuumReference` carry a
  line layer's fit; `suggestions(stats:layers:)` may read them.
- **HDRProcess** (card 0052, id `hdr`, stage linear, off by default): the port of the v9
  runbook's hdrcomp. Luminance (mean of the planes) → grey opening (`GreyMorphology`, radius
  `openRadius` px) so stars never enter the smooth part → three box passes (`BoxBlur`, Kovesi's
  widths for σ `sigma` px, hdrcomp's own approximation) → above t1 = bundle sky + `kneeAboveSky`
  the smooth part becomes t1 + s·asinh((smooth − t1)/s), the detail is put back, one ratio L′/L
  scales every plane. The sky is the mean of the bundle's plane medians and the thresholds are
  absolute above it (PO 2026-10-19: 0.00084 / 0.00118, σ 30, radius 16), never multiples of a
  measured sky. Pinned against hdrcomp's recorded `crop/hdr_only.fits` (max |Δ| 6e-8).
- Shared GPU helpers: `GreyMorphology` (erode/dilate/open, separable, window clipped to the
  image, bit-exact vs a van Herk oracle), `BoxBlur` (edge-clamped x+y passes, one per radius;
  also `MaskBuilder.feather`) and `ScratchTexture` (private
  r32Float intermediates) — encode into the caller's command buffer; reuse them, never a second
  min/max or blur kernel. `BoxBlur` runs Kahan running sums (cost independent of the radius);
  `BoxGaussian` (card 0053) is the legacy `imgops.GaussianBlur` widths for σ on top of it.
- **StarRecompositionProcess** (card 0055, id `star-recomposition`): stardesat's recomposition —
  star layer `max(original − starless, 0)`, chroma scaled by `chroma` around the Rec. 709 luma,
  put back at `presence`, `additive` (stardesat) or `screen` (PixInsight), clamped. The starless
  is the bundle layer `starless` (StarNet's output, `StackKit/StarNet`); defaults chroma 1 /
  presence 1 (identity where original ≥ starless), the PO's 0.25 is a suggestion. Pinned against
  stardesat's recorded `haplus_final` and `stars_25/50/75`.
- **DeliverableExport** + `ExportSettings` (card 0055): the legacy set `final`, `final-starless`,
  `final-{75,50,25}-stars` (the star tiers rendered by `StarRecompositionProcess`), PNG16 /
  TIFF16 (`ImageExport`) / FITS32 (`FITSFile.create`), crop fraction per edge (astrocomp
  rounding), hflip/vflip, `{name}` template (one file name containing `{name}`); everything is
  checked before a file is written. `ExportGuard` refuses a folder under
  `~/Documents/astro/{captures,runs,library,fixtures}` (links resolved, case ignored, R7).
  Card 0091: `starless: nil` (never separated) writes `.final` only, the shaped original, and
  refuses a star tier with `.needsStarless`; `ExportSettings` is `Codable` (the app's `exports`
  record keeps it).
- **Pipelines** (card 0059, `Pipeline/`): `Pipeline` = ordered `PipelineStep`s {recipe, mode
  `auto`|`stop`, `locked`}; `problems(registry:batch:present:)` names an unknown process, a missing
  layer or a linear step after a non-linear one (shown, never reordered). `PipelineRunner` applies
  steps through a `History`: `run` halts *before* a `stop` step (`.stopped(at:)`, the Studio shows
  that process with its recipe), `resume(at:params:)` is « Continue » with the edited values,
  `replay(on:in:bundle:previous:)` starts a new history on another bundle, and a locked step takes
  the same step's output from `previous` (a `PipelineRun`: history + bundle) only when the input is
  the same (original image, bundle, every earlier step) — else it re-runs (`PipelineReuse`). Batch processes
  (host tools) are `BatchProcess` closures injected by id — ProcessKit never imports StackKit —
  and report progress live as `.progress` events. A batch process with `writes: role` (StarNet's
  `.starless`, card 0091) keeps the working image and records its image as that layer
  (`BatchProcess.record`, shared with `StudioSession.apply(_:id:params:onProgress:)`). The first step gets the bundle's stats, each
  later one the stats of the image it receives (`LayerStats.measured`); layers reach every step.
  `PipelineDiff.entries` lists param / mode / lock / process / added / removed differences;
  `Pipeline.json()` / `Pipeline.load` are versioned, each step's recipe read by `Recipe.load` so
  unknown keys and clamps warn as for a recipe. Saved by name in the project with ProjectKit's
  `savePipeline(named:json:)`. The pipeline sidebar (0088) runs it in the Studio.
- **Profiles** (card 0060, `Profile/`, resources `Profiles/*.json`): `Profile` = key (object
  type × camera × filter compositions) + preprocessing (mode, 0070 knob wire keys) + steps (a
  process, the values the profile sets, a fr/en « why » for each) → `pipeline`. Five builtins from
  the PO's validated recipes (M 31 HaPlus, IC 1848 « doux », M 45, mono LRGB+Hα, mono SHO/HOO — the
  mono values are starting points E18 refines). `Profile.load` is strict: an unknown process or
  parameter, a value outside its bounds, a value without both « why » refuse the file — a profile
  is never clamped. `ProfileLibrary` = builtins (read-only resources) + user copies (the project's
  `user_profiles`, through closures): a copy shadows its builtin, `builtin(id:)` still offers it.
  `ProfileProposal.propose` narrows by camera and filters, proposes the only match or the one a
  target was validated on (`examples`), else lists candidates without picking; reasons are values
  the app words. Knob ids and values are 0070 `KnobSchema` knobs (`ProfileKnobTests`).
- `ProcessRegistry`: refuses duplicates and invalid schemas (`.px` without
  `previewExactOnlyAt1to1`, a default outside its bounds or options, infinite bounds);
  `standard()` is validated like any registry and lists the shipped processes (today:
  `channel-combination`, `stretch`, `hdr`, `emission-screens`, `colour-balance`, `sky-desat`,
  `curves`, `saturation`, `star-recomposition`; pipeline order is E15's — `stage` documents it).
- **Colour processes** (card 0053), `Processes/Colour/`, kernels in `Colour.metal` (they share the
  HSL helpers; a runtime-compiled source has no `#include`) and `SkyDesat.metal`; every default is
  the identity, bit for bit:
  - `colour-balance` (linear): `(in + offset) · gain` per channel; untouched values copy. A sky
    region is measured by `regionMedians` (RenderKit's robust median) and only fills
    suggestions: `neutraliseSuggestions` (offsets equalising its medians, level kept) and
    `greySuggestions` (gains after the offsets, green fixed). The region picker is the viewer's
    `PixelRegion`, wired by the Studio panel; a grey gain outside the bounds is not offered.
  - `sky-desat` (linear): the legacy `chromasmooth.go` `sky_desat` passes, brightness-relative
    masks (fractions of the sky level) — stage 1 pulls the chroma toward its star-masked coarse
    field, stage 2 greys the floor, keep-cool gates stage 1 on warm deviations, saturated cores are
    guarded; the pixel mean is preserved. Sky level and chroma σ come from the bundle `LayerStats`
    (refused without them); every band and radius is a parameter. Linear, not after the stretch:
    the bands were tuned on linear data (+0.05 % of sky for the M45 veil). Blurs: `BoxGaussian`.
  - `curves` (non-linear): RGB, R, G, B, luminance (lift by f(Y) − Y, Rec. 709), saturation (HSL
    S) as `points` parameters; `MonotoneSpline` (Fritsch–Carlson, no overshoot) sampled into a
    1024 × 6 LUT texture built at init. RenderKit's `CurveEditor` edits them (`CurveEditorPoints`,
    the app converts to `CurvePoint` and passes `{ MonotoneSpline(points).callAsFunction }`).
  - `saturation` (non-linear): astrocomp's `-sat -sat-masked` (HSL S through the
    `saturationMaskLUT` band on the HSL lightness), the compose star-core desaturation
    (`starDesatMaskLUT` on the luminance) and the `desat` tool's luma blend `k`; the PO's values are suggestions.

## Strings (card 0073)

`Localizable.xcstrings` holds every title a panel shows — process, parameter and palette titles —
in en/fr; the English title is the key, resolved with `ProcessKitResources.title(_:)`.
`ProcessTitleCatalogTests` fails when a registered title has no key or a key no title. Rules:
`Sources/StringCatalog/README.md`.

## Studio (card 0087)

- `History` steps may write layers besides their image (`apply(…, outputs: [LayerRole: AstroImage])`,
  files `step-NNNN-<role>.fits`); `layers()` overlays them, latest per role, for the steps after
  it; undo removes them. `<folder>.json` beside the history folder records steps, undone steps
  and snapshots: `History.reopen(directory:original:header:schema:)` finds the history again.
- `StudioSession` (history + bundle + registry + GPU): `render` (the preview and Apply both come
  from it, a mask applied after the process), `apply`, step outputs overlaid as context layers
  (`role.rawValue` ids), `unavailableReason` (the `Pipeline.problems` rule over the steps so far,
  shown never enforced), `suggestions`. The app wraps it in `StudioModel` (every step mirrored in
  ProjectKit) and `StudioWorkspaceModel` (catalogue, panel, live preview, compare, mask).
- `ImageProcess.promoted(_:)` names advanced parameters the current values make relevant (shown
  without the disclosure); `ImageProcess.steps` gives finer arrow steps (a tenth with ⇧ or ⌥).
  `HistogramHandled` processes (levels, stretch) put their values as handles on the head's
  histogram in the panel.
- A host-tool step (StarNet 0091, background extraction 0092) records its result and the layers
  it wrote with `StudioSession.apply(_:params:result:outputs:)`.
- **Host-tool processes** (card 0093, `PlateSolveProcess`): a registered `ImageProcess` with
  `hostTool = true` — its `render` is the preview only (plate solving: the image itself), so the
  catalogue, panel, help gates and history reopen treat it like any process, while
  `StudioSession.apply(_:params:mask:)` refuses it (`StudioError.needsTool`) and `PipelineRunner`
  runs the injected `BatchProcess` of its id or stops (`PipelineError.toolMissing`); without it,
  `Pipeline.stepProblems` names the step before any run. The pipeline sidebar (0088) injects no
  tool yet: running Siril from a pipeline needs Stop, the report and one-run-at-a-time with the
  Studio's Apply — a follow-up. The app
  injects the tool (`StudioTool`, by id) into `StudioWorkspaceModel`: Apply runs it in the
  background (`startTool`, progress in `toolRun`, Stop = `cancelTool`), records the step only on
  the head it started from, and shows the tool's `toolReport`.
- `ColourCalibrationProcess` (0094) is the second: `requiresSolution` greys it until the head
  carries a WCS (`StudioUnavailable.unsolved`), and `runsTool(_ params)` makes an unticked step
  (`enabled` off, what the dual-band profile ships with its why) the image itself, applied and
  replayed without the tool (`Recipe.runsTool(as:)`). Its sensor / filter / white-reference
  choices are Siril's own names (`SPCCNames`, pinned live against `spcc_list`) — a filter there
  is a product on the camera, not a `Filter` band.
- **WCS per step** (0093): `History` writes each step with the stack header's cards but the
  image's own solution (`FITSHeader.carrying(metadata.wcs)`; `WCS.cards` keeps the cards it was
  read from), so a solve survives later steps, undo, redo and reopen, and the readout follows. A
  geometry step (0090) that moves pixels must give its result the moved `WCS`, or `nil` to drop
  it.
- `.text` parameters (`ParamSpec(id:title:level:text:maxLength:)`): free text, trimmed, empty by
  default — a coordinate the user types or takes from a suggestion; JSON stores a string.

## Host-tool processes with layers (card 0092)

- Background extraction is a host-tool process like plate solving (`hostTool = true`, card
  0093): its `render` is the image itself, Apply runs the tool the app injects
  (`StudioTool`), a pipeline without it names the step (`PipelineError.toolMissing`).
- A host tool may read and write layers: `PipelineRunner.BatchInput` (the head and the bundle's
  layers as the steps so far left them) → `BatchOutput` (the step's image, new layers by role in
  `outputs`, bundle layers rewritten by id in `replaced`). `BatchProcess.init(schema:run:)`
  still wraps a tool that only makes the image; a locked step reused on replay carries its
  layers.
- `History.apply(…outputs:replacing:)`: a rewritten bundle layer (`Ha` after an extraction) is
  read by later steps under the bundle's id and adds no role; `writtenLayers()` (each file read
  once, evicted when no step refers to it) is the overlay `History.context(over:stats:device:)`
  uploads for the Studio and the pipeline runner alike.
- **BackgroundExtractionProcess** (`background-extraction`, linear): `engine` graxpert /
  siril-rbf / siril-polynomial (each engine's values advanced, promoted by the choice),
  `correction`, `applyTo` rgb (the head) / lines (the Hα/OIII/SII layers, the head kept) / all
  (the head and every bundle layer). `run(_:params:extract:)` runs the engine per target, head
  first; the first target's model is the `backgroundModel` output. The app's
  `BackgroundExtractionTool` wires `extract` to StackKit `BackgroundExtraction`; the workspace
  greys an engine whose tool is missing (and divide with Siril, StackKit's
  `BackgroundEngine.supports`) and refuses Apply with the reason — no other engine runs (R2).

To give a host tool layers: return them in `StudioToolResult(…outputs:replaced:)` from a
`StudioTool(step:)`; the Studio records them, the next steps read them.

## How to add a process

1. A type conforming to `ImageProcess` in `ProcessKit/Processes/<Name>/`, its kernel in a
   `.metal` built with `ProcessLibrary` (fast-math off), `.px` parameters divided by
   `context.scale`, and nothing else reading the scale or the purpose.
2. Its schema: stable ids, bounds, units, `simple` for what most users touch.
3. `previewExactOnlyAt1to1 = true` if any parameter is `.px`.
4. Register it in `ProcessRegistry.standard`.
5. Write `HelpKit/Help/{fr,en}/process/<id>.md`: ≤ 5 lines, ≤ 90 words each (gated).
6. Add its title and every parameter title, en + fr, to `ProcessKit/Localizable.xcstrings` (gated).
7. Tests: `ProcessContracts(...).violations(of:params:)` is empty, plus the kernel against a CPU
   oracle with its tolerance stated.

Allowed dependencies: `ImageKit`, `RenderKit` (`Tests/TestSupport/BoundaryRules.swift`).
