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
  where a measurement API needs it (`XCTMetric` for GPU/frame budgets).
- **Table-driven**: `@Test(arguments: [...])` over an array of cases; one case = one row.
- Naming: `test<Type>_<Method>_<Scenario>` or a sentence string in `@Test("…")`; one behaviour
  per test.
- Test targets colocated per module in `Package.swift` (`<Module>Tests`); fixtures under
  `Tests/<Module>Tests/Fixtures/` and **pixel-free** (JSON, scripts, checksums). Images and
  anything derived from captures live in `~/Documents/astro/fixtures/` and the test **skips**
  (`try #require(...)`/`withKnownIssue`) when they are absent — those are *live* tests, run on
  the PO's Mac before a PR, never on CI.
- Oracles: every port from the legacy Go engine (`../stacking-astro`) is pinned by a recorded
  oracle (emitted Siril scripts, frame selections, master checksums, reference renders); a
  numeric tolerance is stated in the test, never implied.
- GPU: a Metal shader is tested against a CPU oracle on synthetic textures (ramps, noise fields,
  checkerboards) with an explicit tolerance; frame-budget tests are live-only.
- No sleeps, no shared mutable state, no execution-order reliance; temp dirs per test.

## When to write tests / when not

**Write:** every function with non-trivial logic; every search/filter; every create/update hook; every handler with business logic; auth and permission logic; pipeline/queue changes.

**Skip:** trivial CRUD that just calls the ORM; pure configuration; route/DI wiring.
