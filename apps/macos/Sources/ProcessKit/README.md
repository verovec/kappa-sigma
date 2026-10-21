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
  `v` at scale 2 = `v / 2` at scale 1, the process's other `.px` values halved in the reference
  too), bit-exact.
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
  hidden in the shader. No panel yet: the Studio renders the schema generically (0075/0076).
- **Colour processes** (card 0053), `Processes/Colour/`, kernels in `Colour.metal` (they share the
  HSL helpers; a runtime-compiled source has no `#include`) and `SkyDesat.metal`; every default is
  the identity, bit for bit:
  - `colour-balance` (linear): `(in + offset) · gain` per channel, `linked` = the green gain for
    all. A sky region is measured by `regionMedians` (RenderKit's robust median) and only fills
    suggestions: `neutraliseSuggestions` (offsets equalising its medians, level kept) and
    `greySuggestions` (gains after the offsets, green fixed). The region picker is the viewer's
    `PixelRegion`, wired by the Studio panel.
  - `sky-desat` (linear): the legacy `chromasmooth.go` `sky_desat` passes, brightness-relative
    masks (fractions of the sky level) — stage 1 pulls the chroma toward its star-masked coarse
    field, stage 2 greys the floor, keep-cool gates stage 1 on warm deviations, saturated cores are
    guarded; the pixel mean is preserved. Sky level and chroma σ come from the bundle `LayerStats`
    (refused without them); every band and radius is a parameter. Linear, not after the stretch:
    the bands were tuned on linear data (+0.05 % of sky for the M45 veil).
  - `curves` (non-linear): RGB, R, G, B, luminance (lift by f(Y) − Y, Rec. 709), saturation (HSL
    S) as `points` parameters; `MonotoneSpline` (Fritsch–Carlson, no overshoot) sampled into a
    1024 × 6 LUT texture built at init. RenderKit's `CurveEditor` edits them (`CurveEditorPoints`,
    the app converts to `CurvePoint` and passes `{ MonotoneSpline(points).callAsFunction }`).
  - `saturation` (non-linear): astrocomp's `-sat -sat-masked` (HSL S through the
    `saturationMaskLUT` band on the HSL lightness), the compose star-core desaturation
    (`starDesatMaskLUT`) and the `desat` tool's luma blend `k`; the PO's values are suggestions.
- `BoxGaussian`: `imgops.GaussianBlur` on the GPU (three Kovesi boxes over `Mask.metal`'s
  edge-clamped box pass), encoded into a render's command buffer — reuse it for any blur.
- `ProcessRegistry`: refuses duplicates and invalid schemas (`.px` without
  `previewExactOnlyAt1to1`, a default outside its bounds or options, infinite bounds);
  `standard()` is validated like any registry and lists the shipped processes (today:
  `channel-combination`, `stretch`, `colour-balance`, `sky-desat`, `curves`, `saturation`; the
  menu order, pipeline order comes from `stage`).

## Strings (card 0073)

`Localizable.xcstrings` holds every title a panel shows — process, parameter and palette titles —
in en/fr; the English title is the key, resolved with `ProcessKitResources.title(_:)`.
`ProcessTitleCatalogTests` fails when a registered title has no key or a key no title. Rules:
`Sources/StringCatalog/README.md`.

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
