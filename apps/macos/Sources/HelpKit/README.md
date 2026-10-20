# HelpKit

Help content: process cards, "why this value", the first-stack guide, in French and English
(design §6).

## What exists (card 0049)

- `Help/<locale>/process/<process id>.md`: one card per registered process and locale (`fr`,
  `en`), bundled as a resource folder.
- `HelpIndex`: reads cards from a root folder (`bundled` for SwiftPM builds, `init(bundle:)` for
  the packaged app's resolved bundle) and runs the **coverage gate**: every process id needs a
  card in each locale, at most 5 lines and 90 words. `ProcessSchemaTests` gates
  `ProcessRegistry.standard` against the bundled cards.

## Glossary (card 0074)

- `Help/<locale>/glossary.json`: term id → `label` + one-line `definition` (≤ 24 words), the
  astronomer's words of each locale (brutes, darks, flats, offsets, dark-flats…). `Glossary`
  reads it; `problems(ids:)` / `stale(ids:locale:)` are its gate.
- Ids are derived from the catalogs that own the vocabulary, never listed twice: the app's
  `GlossaryTerms.swift` maps `FrameType`, `Filter`, `FilterSet`, `ColorChoice`, `ColorModel`
  (StackKit) and `JourneyStage` to `frame.light`, `filter.ha`… and `GlossaryTests` enumerates
  their `allCases` — a case added without its term fails.
- Filters keep their short name (`Ha`) on screen in both languages; the term is the long name.

## How to extend

- A new process ships its two cards in the same PR, or the gate fails.
- A new case in a glossary-backed enum ships its `fr` and `en` terms in the same PR.
- Card 0061 brings the renderer (Markdown → panel) and the other help content; in the packaged
  app, pass the bundle resolved from `Contents/Resources` (see ImageKit's `KitBundle`) to
  `HelpIndex(bundle:)` — `Bundle.module` does not look there.
- Allowed dependencies: none (`Tests/TestSupport/BoundaryRules.swift`).
