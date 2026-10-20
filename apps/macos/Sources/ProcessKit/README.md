# ProcessKit

The Studio's process seam: parameter schemas, the GPU render shared by preview and Apply, the
non-destructive history, recipes and the registry (design §2, §4.1).

## What exists (card 0049)

- `ImageProcess` (named so to avoid `Foundation.Process`): `id`, `title`, `stage`
  (linear/nonlinear/any), `requires: [LayerRole]`, `schema`, `previewExactOnlyAt1to1`,
  `render(_:stats:into:context:)`, `suggestions(stats:)`. R2: `render` reads the image, the
  bundle `LayerStats` and `params`, never measures the image to set itself; measurements return
  as `Suggestion`s.
- `ParamSchema` / `ParamSpec` (number with bounds, flag, choice; `ParamUnit` none/px/sigma/opacity;
  `ParamLevel` simple/advanced with the display rule `visible(disclosed:promoted:)`), `ParamSet`
  (schema order, clamped, NaN refused, encoded as ordered JSON; no decoder: stored values come
  back through `ParamSet.loading`, which validates them and returns what it refused).
- `GPUImage` (r32Float planes, read/write, shared), `ProcessRunner` (synchronous run),
  `ProcessLibrary` (pipelines with RenderKit's fast-math-off compile options).
- `ProcessContracts`: **PreviewEqualsApply**, **NoHiddenState**, **PxUnitsScale** (a `.px` value
  `v` at scale 2 = `v / 2` at scale 1), bit-exact.
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
- `ProcessRegistry`: refuses duplicates and invalid schemas (`.px` without
  `previewExactOnlyAt1to1`, a default outside its bounds or options, infinite bounds);
  `standard()` is validated like any registry and lists the shipped processes (today:
  `channel-combination`).

## How to add a process

1. A type conforming to `ImageProcess` in `ProcessKit/Processes/<Name>/`, its kernel in a
   `.metal` built with `ProcessLibrary` (fast-math off), `.px` parameters divided by
   `context.scale`, and nothing else reading the scale or the purpose.
2. Its schema: stable ids, bounds, units, `simple` for what most users touch.
3. `previewExactOnlyAt1to1 = true` if any parameter is `.px`.
4. Register it in `ProcessRegistry.standard`.
5. Write `HelpKit/Help/{fr,en}/process/<id>.md`: ≤ 5 lines, ≤ 90 words each (gated).
6. Tests: `ProcessContracts(...).violations(of:params:)` is empty, plus the kernel against a CPU
   oracle with its tolerance stated.

Allowed dependencies: `ImageKit`, `RenderKit` (`Tests/TestSupport/BoundaryRules.swift`).
