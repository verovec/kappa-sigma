# RenderKit

The Metal viewer and shaders: zoom/pan, 1:1 region, display stretch, histogram, and the kernels the
processes run (design §4.1, §4.6).

## What exists (card 0042)

- **STF** (`STF/`, CPU, the oracle): `MTF.apply` (closed form `((m − 1)x) / ((2m − 1)x − m)`),
  `STFParameters.display` (clip to [c0, c1], rescale, MTF; off = clamp), `AutoSTF.compute` —
  Siril's autostretch: c0 = median − 2.8·MADN, m maps median − c0 to 0.25, c1 = 1; linked = the
  mean of the channels' statistics. A **display transform only** (R2): the planes never change.
- **GPU** (`GPU/`, `Shaders/`):
  - `ImageTexture`: one `r32Float` texture per plane, mip levels = ImageKit's `Pyramid` (2×2 means).
  - `DisplayPipeline` (`display` kernel): view pixel → image via `origin + (gid + ½)·scale`, mip
    level `floor(log2 scale)`, optional STF per channel, clipping overlay (≥ 1 red, ≤ 0 blue),
    compare (reference everywhere, or left of a split column), bottom-up rows flipped
    (`ROWORDER`), and the process mask as a red tint (`ViewerFrame.maskOverlay`, texture 7).
    Pinned to the CPU STF within 1/65535 (`DisplayPipelineTests`).
  - `Histogram` (`histogram` kernel): 256 bins × channel of clamp(x), sampled every `stride`
    pixels inside a region; exact counts (atomics).
  - `ShaderLibrary`: a bundled `RenderKit.metallib` if present, else `makeLibrary(source:)` of the
    same `.metal` files (Metal 3.1, `mathMode = .safe`, precise functions); `ShaderTypes.h` is
    inlined since the runtime compiler has no include path.
  - `ShaderLayoutProbe`: the `shaderLayout` kernel reads every uniform field back, so the Swift
    mirrors (`DisplayUniforms`, `HistogramUniforms`) cannot drift from `ShaderTypes.h`.
- **Viewer** (`Viewer/`):
  - Plain Swift, tested without a GPU: `ViewTransform` (fit, 1:1, zoom about the cursor bounded
    1/64…64, pan, drag → `PixelRegion`), `PixelReadout` (exact plane values, RA/Dec from
    `ImageMetadata.wcs`, sexagesimal text), `ViewerModel` (`@Observable`, main actor: stretch
    auto/manual/off, linked, tools pan/region/split, ⌥ compare key, hover readout, histogram).
  - `ViewerFrame` → `ViewerRenderer`: display + histogram in one command buffer per frame.
  - UI: `ViewerView` (SwiftUI) = `ViewerMTKView` (draws on demand; scroll/pinch zoom, drag with the
    tool, ⌥ held = reference, `zoomToFit:` ⌘0 / `zoomToActualSize:` ⌘1 via the responder chain)
    + region outline + `ViewerPanel` (every stretch number shown, manual sliders, histogram,
    readout).
- Frame budget (`LiveViewerPerfTests`, live-only): 22 Mpx RGB, 3024×1964 view, STF + histogram:
  **1.5 ms** mean GPU time on the M5 Pro (budget 16 ms).

## Strings (card 0073)

`Localizable.xcstrings` holds the viewer chrome in en/fr, compiled by `CatalogPlugin` into
`RenderKitResources.bundle` (the same bundle the shaders load from); resolve with
`.renderKit("…")`. `ViewerPanel` reads its words from it (tool and stretch labels included,
never `rawValue.capitalized`) and formats its numbers in the view's `\.locale` (card 0074).
Rules: `Sources/StringCatalog/README.md`.

## Design system (card 0075)

`DesignSystem/` holds what every panel shares, so no screen picks its own colours:

- **Tokens.** `DesignColor` (surface, canvas, text levels, status ok/attention/error/unavailable,
  region outline, plot colours): a light and a dark sRGB value each, resolved by AppKit with the
  view's appearance (`NSColor(name:dynamicProvider:)` — no asset catalog, CLT has no `actool`).
  Text and status colours keep ≥ 4.5:1 on `surface` in both appearances; `canvas` (around the
  image, also the display kernel's `canvasGrey` uniform) is R = G = B and never the accent
  (`DesignTokensTests`). `DesignStatus` pairs each status with an SF Symbol: never colour alone.
  `DesignMetrics`: spacing, radii, `valueFont` (monospaced digits).
- **Components** (`Components/`): `MetricValue` (label, formatted value, unit, delta, status),
  `StatusBadge`, `ParameterRow` over a `ParameterValue` (slider + field in the user's notation,
  reset, « Default » badge on the exact default, « why » on hover), `InstallCard` over an
  `InstallCardModel` (re-check asks the `locate` closure; never a fallback, R2), `EmptyState`,
  `SectionHeader`, `CurveEditor` over `CurveEditorPoints` (card 0053). Values arrive
  **formatted**: RenderKit never imports the app, so the caller passes `AstroFormat` strings or
  `format`/`parse` closures.
- **Accessibility** (`Accessibility/`, card 0079): every interactive control goes through
  `.accessible(_ id: AccessibilityID?, label:)` (or `verbatim:` for a glossary term), which sets its
  VoiceOver label and identifier and reports both to `AccessibilityAudit.Key`. Identifiers come
  from the one `AccessibilityID` namespace (`fr.astrostack.parameter.<key>.slider`, `.journey.<stage>`…),
  built from stable keys the caller passes (`ParameterRow(…, key:)`, `CurveEditor(…, key:)`), never
  from a title. SwiftUI builds no accessibility tree without an assistive client, so the app's
  `AccessibilityAuditTests` read the reported entries of the hosted gallery and workspace, and
  count raw `Button`/`Slider`/`TextField`/`Toggle`/`Picker`/`Link` against `.accessible` in each
  component's source. A List's rows report from the List (table cells do not propagate).
  The environment's `guideTarget` (card 0061) rings the `.accessible` control of that id — the
  first-stack guide points at real controls this way — and the entry reports `highlighted`.
- **Gallery.** `ComponentGallery` shows every component in every state; the app opens it from
  Window › Component Gallery in debug builds, and `ComponentGalleryTests` attaches its PNGs in
  light/dark × fr/en.
- Rules: views use `DesignColor.<token>.color`, never `Color.red/.orange/.yellow/.green/.blue`
  (`scripts/hygiene.sh` rule 7); a new component goes in `Components/`, gets a gallery entry,
  catalog words (`DesignSystemCatalogTests`) and `.accessible` on each of its controls; a new token gets its light and dark value and, if
  text sits on it, joins the contrast test.

## Coordinates

View coordinates are drawable pixels (points × backing scale), top-left origin. `ViewTransform`
and `ViewerFrame.region` are in **display rows** (top of the frame first); `PixelReadout`, `WCS`
and the histogram use **stored rows** (`frame.storedRegion`, `ViewerModel.hover` convert).

## How to extend

- A kernel: add it to a `.metal` file in `Shaders/` (or a new file listed in
  `ShaderLibrary.sourceFiles`), its name to `ShaderLibrary.kernelNames`, its parameter struct to
  `ShaderTypes.h` with plain `float`/`uint`/`float[4]` fields, a Swift mirror, and the fields to the
  `shaderLayout` kernel + `ShaderLayoutProbe`. Test it against a CPU oracle on synthetic textures
  with a stated tolerance.
- Fast-math stays off for every oracle-pinned kernel. Runtime compilation until E19 (no Xcode
  needed); `MetalToolchain` tests the precompiled path when `xcrun metal` exists.
- Viewer logic goes in plain Swift (`ViewTransform`, `ViewerModel`) so it tests without a GPU; the
  AppKit/SwiftUI layer only forwards events.
- RenderKit is one of the two modules allowed to import SwiftUI/AppKit (its views). Allowed
  dependencies: `ImageKit` (`Tests/TestSupport/BoundaryRules.swift`).
