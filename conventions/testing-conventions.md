# Testing Conventions

## Guiding Principles (all languages)

1. **Consistency over cleverness** — every test follows the same structure, naming, and assertion style.
2. **Protect critical paths** — focus on code where breakage cascades: data integrity, authentication, core logic, public API contracts.
3. **Tests are documentation** — names and structure read as a specification.
4. **Stability over coverage** — a flaky test is worse than no test. Every test is deterministic and independent (no shared mutable state, no execution-order reliance).
5. **Test modifications are breaking changes** — editing or deleting an existing test changes the contract it protected. That requires explicit justification.

General: arrange-act-assert structure; tests colocated with the code they test; clean state at the **start** of each test, not the end; prefer real dependencies (real DB in a container) over mocks where practical.

## Swift (the whole codebase)

- Framework: **Swift Testing** (`@Test`, `#expect`, `#require`), `@Suite` per type; XCTest only
  where a measurement API needs it (`XCTMetric` for GPU/frame budgets, local-only).
- **Table-driven**: `@Test(arguments: [...])` over an array of cases; one case = one row;
  `zip(a, b)` for pairwise, never an accidental Cartesian product.
- Naming: `test<Type>_<Method>_<Scenario>` or a sentence string in `@Test("…")`; one behaviour
  per test.
- Test targets colocated per module in `Package.swift` (`<Module>Tests`); fixtures under
  `Tests/<Module>Tests/Fixtures/` and **pixel-free** (JSON, scripts, checksums).
- **Live tests** (host tools, images, anything derived from captures under
  `~/Documents/astro/fixtures/`): the suite name starts with `Live`, carries the shared
  `.liveFixtures` condition trait (skips, with the reason, when the fixture root or the tool is
  absent), `.tags(.live)`, `.serialized` when it touches Siril or a scratch dir, and a
  `.timeLimit(.minutes(n))`. They run on the PO's Mac before a PR (`just check`), never on CI;
  `just test-unit` (`swift test --skip Live`) is the fast loop.
- **Oracles**: every port from the legacy Go engine (`../stacking-astro`) is pinned by a recorded
  oracle (emitted Siril scripts, frame selections, master checksums, reference renders). Bytes are
  compared only for what Siril produces (scripts, masters); everything numeric asserts
  `meanAbs`, `maxAbs` and PSNR against a tolerance written in the test, never implied. Goldens that
  live outside the repo have a committed manifest (path, sha256, tolerance, tool versions); the
  test checks the hash before comparing; `RECORD=1` re-records.
- **GPU**: a Metal shader is tested against a CPU oracle on synthetic textures (ramps, noise
  fields, checkerboards) with an explicit tolerance; the test skips when
  `MTLCreateSystemDefaultDevice()` is `nil`; frame-budget and tight-parity tests are live-only
  (the hosted runner's GPU is paravirtualised).
- Text snapshots (`swift-snapshot-testing`) for `.ssf` scripts, JSON plans and 8-bit previews;
  never for float32 data. Exit tests (`#expect(processExitsWith:)`) pin invariant preconditions.
- Diff images go to `Attachment.record(…, as: .png)`; CI uploads `--attachments-path` on failure.
- **Contract tests** are shared: every registered process passes `PreviewEqualsApply`,
  `NoHiddenState`, `PxUnitsScale`; every module passes the module-boundary test; a process without
  a fr+en help card fails the coverage gate.
- No sleeps, no shared mutable state, no execution-order reliance; temp dirs per test (a custom
  `TestScoping` trait provides the scratch dir); clean state at the start.
- Benchmarks (`package-benchmark`) run locally with tight thresholds (`just bench`); on CI only
  wide relative thresholds are trusted.

## When to write tests / when not

**Write:** every function with non-trivial logic; every search/filter; every create/update hook; every handler with business logic; auth and permission logic; pipeline/queue changes.

**Skip:** trivial CRUD that just calls the ORM; pure configuration; route/DI wiring.
