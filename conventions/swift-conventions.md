# Swift Coding Conventions

House style for the Swift 6 / SwiftUI / Metal codebase (`apps/macos`). Tests: `testing-conventions.md`.
Persistence (SQLite in ProjectKit): `database-conventions.md`. The *why* behind every rule here,
with sources, is `docs/engineering/swift-quality-playbook.md` — read it once per epic.

## Structure

- SwiftPM is the source of truth (`Package.swift`, `swift-tools-version: 6.2`); one module per
  responsibility (`ImageKit`, `RenderKit`, `ProcessKit`, `ProjectKit`, `StackKit`, `HelpKit`,
  `AstroStackApp`). A module never imports the app target; UI lives only in `AstroStackApp` and
  `RenderKit` views. A kit that accumulates `nonisolated` escapes contains UI: split it.
- Every target carries the same `swiftSettings`: `.swiftLanguageMode(.v6)`,
  `.enableUpcomingFeature("NonisolatedNonsendingByDefault")`,
  `.enableUpcomingFeature("InferIsolatedConformances")`,
  `.enableUpcomingFeature("InternalImportsByDefault")`, `.treatAllWarnings(as: .error)`,
  `.treatWarning("DeprecatedDeclaration", as: .warning)`. **Only** `AstroStackApp` adds
  `.defaultIsolation(MainActor.self)`. `.strictMemorySafety()` on ProjectKit, ProcessKit, HelpKit.
- Access levels: `package` for what sibling kits and tests need, `public` only for what the app
  consumes, `@testable import` never (reserved for a justified internal seam). Framework imports
  are `internal import` unless a type must appear in the module's API.
- Files ≤ 300 lines, types ≤ 250, functions ≤ 50 (SwiftLint enforces), one type per file,
  `// MARK:` sections.

## Concurrency (Swift 6.2 "approachable concurrency")

- Default to main-actor or non-Sendable types; `Sendable` conformance is earned, never
  `@unchecked`. Image buffers are non-Sendable `final class` wrappers passed with `sending`.
- CPU-bound `async` work (pyramid, statistics, Accelerate ports) is `nonisolated` **and**
  `@concurrent`; without it a `nonisolated async` function runs on the caller's actor and a stack
  called from the UI blocks the main thread.
- One `actor` per genuinely shared state (Siril session, texture cache), never one per module;
  actors are not queues.
- Structured concurrency only: `Task`, `TaskGroup`, `AsyncStream`; no `DispatchQueue`, no
  `Task.detached`; cancellation is checked in every loop that can run > 100 ms.

## Errors and values

- Public kit APIs use untyped `throws` with a module error enum carrying the context a user can act
  on (path, frame, command); typed `throws(XError)` only inside a module where the caller switches
  exhaustively. `throws` over optional-for-failure; `Result` only to store or forward an outcome.
  Never `fatalError` on user data; `precondition` on invariants only (pinned by exit tests).
- Value types first (`struct`/`enum`); classes only for identity (actors, document, GPU resources).
- Units are explicit in names and types: `px`, `sigma`, `ms`, `seconds`; a parameter in pixels is
  scaled by the preview level inside the renderer, never by the caller.
- Dependencies are explicit: a client is a struct of closures (`SirilRunner`, `ToolLocator`)
  passed through the initialiser; tests substitute endpoints with recorded outputs. No service
  locator, no global singletons.

## Pixels, Metal, Accelerate

- Planes are `[Float32]` (planar, not interleaved); the GPU format is `r32Float`; storage
  `.shared` for CPU-filled planes (`makeBuffer(bytesNoCopy:)`, page-aligned), `.private` for GPU
  intermediates. No `CIImage`.
- Metal 3 APIs. Shaders: one `.metal` per process, parameter structs in one shared C header so
  Swift and MSL share a single definition. Two load paths (runtime `makeLibrary(source:)` and
  precompiled `.metallib`) with identical compile options, both tested.
- Fast-math is off for every oracle-pinned kernel (`mathMode = .safe`,
  `mathFloatingPointFunctions = .precise`); reductions use a fixed order; no atomics in pinned
  kernels. MPS is allowed for unpinned stock operators only.
- Every Metal kernel has a CPU oracle in its tests. Preview and Apply run the same shader.
- Heavy CPU math goes through Accelerate (`vDSP`, `vImage.PixelBuffer<PlanarF>`); no hand-rolled
  loops where vDSP exists. Hot loops may use `Span`/`InlineArray` (macOS 26 floor).

## Persistence, processes, localisation

- SQLite through GRDB (`DatabasePool` per open document). Migrations are SQL pairs
  `ProjectKit/Migrations/NNNN_name.{up,down}.sql` run by ProjectKit's `Migrator` (GRDB's
  `DatabaseMigrator` has no down migration — card 0068); one pair per change, never edited after
  merge, `SCHEMA.md` kept current. The document is an `NSDocument` over the `.astrostack` package
  so the database and images stay in place on save.
- External tools run through `swift-subprocess` (never `Foundation.Process`): FIFOs opened by us,
  timeout via task group, teardown SIGTERM → SIGKILL. A missing tool is a typed error surfaced
  as an install card, never a fallback (R2).
- Strings in a `Localizable.xcstrings` per target, resolved with `bundle: #bundle`; help content
  is Markdown in resources. No generated catalog symbols in the MainActor-isolated app target.

## Legacy Go as reference, never as code

- The old engine (`../stacking-astro/internal/...`) is read to port a rule, then the rule is
  written in Swift with its tests translated. No Go, no cgo, no helper binary in this repo.
- Recorded oracles (scripts, selections, checksums) pin each port — see `testing-conventions.md`.

## Style and observability

- `swift format lint --strict` (config `apps/macos/.swift-format`) and SwiftLint
  (`apps/macos/.swiftlint.yml`) pass: `just lint`. No force unwraps outside tests; no `print`.
- One `Logger(subsystem: "fr.astrostack", category: "<Kit>/<topic>")` per topic; interpolated
  values stay private unless marked `privacy: .public`. `OSSignposter` intervals around every GPU
  pass and every Siril step.
- Comments say *why*, never *what*. Public and package declarations carry a one-line doc comment.
