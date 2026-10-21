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

## Renderer and guide (card 0061)

- `HelpMarkdown.parse`: the subset help is written in — one paragraph per line, `- `/`* `/`1. `
  items, `**bold**`, `*italic*`/`_italic_`. Headings, links, code, an unclosed marker stay plain
  text; it never fails. The app's `HelpText` view draws the blocks.
- `Help/<locale>/guide/first-stack.md`: the first-stack guide, one step per line opening on a
  bold title; `HelpIndex.guide(locale:)` reads it, `guideProblems(steps:)` gates the count per
  locale and ≤ 40 words a step. The app's `FirstStackGuide` pairs each line with the control it
  points at (an `AccessibilityID`), so the step count lives there.
- Profiles' « why » lines are ProcessKit data (0060); `HelpCoverageTests` (ProcessKit) gates
  them in fr and en with the process cards.

## How to extend

- A new process ships its two cards in the same PR, or the gate fails.
- A new case in a glossary-backed enum ships its `fr` and `en` terms in the same PR.
- A guide step added or removed changes both locale files and `FirstStackGuide.steps` together;
  `FirstStackGuideTests` checks every target is a control a hosted view reports.
- In the packaged app, pass the bundle resolved from `Contents/Resources` (see ImageKit's
  `KitBundle`) to `HelpIndex(bundle:)` — `Bundle.module` does not look there (`AppGlossary.help`).
- Allowed dependencies: none (`Tests/TestSupport/BoundaryRules.swift`).
