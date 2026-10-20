# Swift Coding Conventions

House style for the Swift 6 / SwiftUI / Metal codebase (`apps/macos`). Tests: `testing-conventions.md`.
Persistence (SQLite in ProjectKit): `database-conventions.md`.

## Structure

- SwiftPM is the source of truth (`Package.swift`); one module per responsibility (`ImageKit`,
  `RenderKit`, `ProcessKit`, `ProjectKit`, `StackKit`, `HelpKit`, `AstroStackApp`). A module never
  imports the app target; UI lives only in `AstroStackApp` and `RenderKit` views.
- Files ≤ ~300 lines, one type per file, `// MARK:` sections. Public API is the exception, not the rule.
- Strict concurrency on (Swift 6). Shared mutable state behind an `actor`; UI state is `@MainActor`
  `@Observable`. No `DispatchQueue` in new code; `Task`, `AsyncStream`, `TaskGroup`.

## Errors and values

- Typed errors (`enum XError: Error`) with the context a user can act on; never `fatalError` on
  user data. `throws` over optional-for-failure.
- Value types first (`struct`/`enum`); classes only for identity (actors, document, GPU resources).
- Units are explicit in names and types: `px`, `sigma`, `ms`, `seconds`; a parameter in pixels is
  scaled by the preview level inside the renderer, never by the caller.

## Pixels

- Planes are `[Float32]` (planar, not interleaved); the GPU format is `r32Float`. No `CIImage`.
- Every Metal kernel has a CPU oracle in its tests. Preview and Apply run the same shader.
- Heavy CPU math goes through Accelerate (`vDSP`, `vImage`); no hand-rolled loops where vDSP exists.

## Legacy Go as reference, never as code

- The old engine (`../stacking-astro/internal/...`) is read to port a rule, then the rule is
  written in Swift with its tests translated. No Go, no cgo, no helper binary in this repo.
- Recorded oracles (scripts, selections, checksums) pin each port — see `testing-conventions.md`.

## Style

- `swift-format` (repo config), `just lint` must pass. No force unwraps outside tests; no `print`,
  use `os.Logger` with a per-module category. Comments say *why*, never *what*.
