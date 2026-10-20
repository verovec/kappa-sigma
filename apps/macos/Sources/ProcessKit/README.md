# ProcessKit

The Studio's process registry: parameter schemas, history, recipes, pipelines and breakpoints
(design §2, §4.1).

**State:** empty module (card 0040). Card 0049 brings the `Process` protocol and its contract tests.

**How to extend:** every process passes the shared contracts (`PreviewEqualsApply`, `NoHiddenState`,
`PxUnitsScale`) and ships a fr+en help card; no process measures the image to change its own
settings (R2). Allowed dependencies: `ImageKit`, `RenderKit` (`Tests/TestSupport/BoundaryRules.swift`).
