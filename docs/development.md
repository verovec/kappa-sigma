# Development

## Toolchain

- macOS 26 with the Command Line Tools (Swift 6.2 or later). Xcode 26 is only needed for the
  precompiled Metal shaders, Instruments and signing; until then shaders compile at runtime.
- [`just`](https://github.com/casey/just) and `swiftlint` (`just setup` installs it); `swift format`
  ships with the toolchain.
- For the live tests: Siril 1.4.x, GraXpert, StarNet2 and the fixtures under
  `~/Documents/astro/fixtures`.

`just doctor` reports what is present and what is missing.

## Recipes

| Command | What it does |
|---------|--------------|
| `just` | List every recipe |
| `just setup` | Install swiftlint and the pre-push hook, then run `just doctor` |
| `just app-build [swift build args]` | Assemble `apps/macos/.build/AstroStack.app` (ad-hoc signed); debug unless `-c release` |
| `just app-run [project.astrostack]` | Build the app and open it, optionally on a project |
| `just app-run-release [project.astrostack]` | The same with the optimized build, for real runs (replaces the debug bundle) |
| `just test` | The whole suite, live tests included |
| `just test-unit` | Everything except the `Live…` suites (the fast loop) |
| `just test-live` | Only the live suites (host tools and fixtures) |
| `just lint` / `just fmt` | `swift format lint --strict` and `swiftlint --strict` / format in place |
| `just coverage` | Line coverage report under `apps/macos/.build/coverage` |
| `just hygiene` | Repository gate: Swift only, no data, README artwork only, links resolve |
| `just check` | The pre-push gate: hygiene, lint, app build, full suite |
| `just ci` | Exactly what CI runs |

## Tests

Tests use Swift Testing, table-driven, colocated per module (`apps/macos/Tests/<Module>Tests`).
Every Metal kernel is checked against a CPU oracle; every port of the legacy engine is pinned by a
recorded oracle. Live suites (names starting with `Live`) need the host tools and the fixtures; they
skip themselves, with the reason, when either is missing. Rules:
[`conventions/testing-conventions.md`](../conventions/testing-conventions.md).

## Continuous integration

GitHub Actions runs two jobs on every pull request: `test continuity` (the suite may only grow; an
edited or deleted test needs a `Test-change:` line in the PR body) and `hygiene · lint · build ·
test` (`just ci` on the maintainer's Mac as a self-hosted runner, live suites skipped). CI runs on
pull requests only. The hygiene gate is `scripts/hygiene.sh`, run by both jobs and pinned rule by
rule by `RepoHygieneTests`. The coverage floor is in `apps/macos/.coverage-floor`: 95%, fixed by the PO (24/10); a card
never moves it.

## Conventions

House rules live in [`conventions/`](../conventions/): Swift, tests, SQLite, commits, `just`
recipes, README. The reasoning behind every gate and every technical decision of the Swift port
(concurrency model, Metal 3, GRDB, swift-subprocess, oracles) is in
[`engineering/swift-quality-playbook.md`](engineering/swift-quality-playbook.md).

## Workflow

Work is planned as cards grouped in epics (E10 to E22), kept locally in `roadmap.md` and `cards/`
(not versioned). Each card is one branch, one pull request, strict TDD, a code review, and a merge
only when both CI jobs are green (`just merge <pr>`).
