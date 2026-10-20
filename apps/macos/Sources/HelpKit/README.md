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

## How to extend

- A new process ships its two cards in the same PR, or the gate fails.
- Card 0061 brings the renderer (Markdown → panel) and the other help content; in the packaged
  app, pass the bundle resolved from `Contents/Resources` (see ImageKit's `KitBundle`) to
  `HelpIndex(bundle:)` — `Bundle.module` does not look there.
- Allowed dependencies: none (`Tests/TestSupport/BoundaryRules.swift`).
