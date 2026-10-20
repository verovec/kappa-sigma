# Kappa-Sigma

Native macOS app for deep-sky astrophotography: stack your captures with Siril, then finish them in a
PixInsight-like Studio with real-time Metal previews — every setting visible, explained and yours.

The previous web engine (Go) lives in the sibling repo `stacking-astro` and is only read as a
reference while its rules are ported to Swift. Design: [`docs/design/astrostack-macos.md`](docs/design/astrostack-macos.md).

## AstroStack 2 (work in progress)

**State on 2026-10-20 (card 0040):** the app skeleton exists, nothing astronomical runs yet.

- `just app-run` builds `AstroStack.app` and opens a project window; a project is a `.astrostack`
  package holding `project.db`, created by File › New Project / Save, reopened by File › Open.
- The window is empty: import, preprocessing (Siril) and the Studio arrive with the next roadmap
  cards (epics E10–E19), preprocessing first.
- Modules exist as empty seams with a README each (`apps/macos/Sources/*/README.md`); their
  boundaries are pinned by a test per module.
- Builds with the Command Line Tools alone (Swift 6.2+); Xcode is only needed later for the Metal
  Toolchain, Instruments and signing.

## Quickstart

```sh
just setup      # swiftlint + pre-push hook, then a host check (`just doctor`)
just app-run    # build apps/macos/.build/AstroStack.app and open it
just check      # hygiene + lint + build + full suite — the pre-push gate
```

## Prerequisites (macOS 26 host)

- Command Line Tools with Swift 6.2+ (or Xcode 26), `just`, `swiftlint` (`just setup` installs it;
  `swift format` ships with the toolchain)
- Later cards: Siril 1.4.x (`/Applications/Siril.app`), GraXpert, StarNet2 (your own install — never
  bundled); Xcode 26 with the Metal Toolchain for precompiled shaders and profiling
- Your data in `~/Documents/astro/{captures,runs,library}` — read-only for the app, never in a repo

## Architecture

Swift 6 only. Modules (SwiftPM, `apps/macos/Package.swift`): `ImageKit` (FITS, planes, pyramid),
`RenderKit` (Metal viewer and shaders), `ProcessKit` (processes, history, recipes), `ProjectKit`
(the `.astrostack` package and its SQLite database), `StackKit` (preprocessing: inspect,
calibration library, Siril driver, grading, stacking), `HelpKit`, and the `AstroStackApp`
executable (AppKit document lifecycle, SwiftUI content). Siril, GraXpert and StarNet are host tools
driven by `StackKit`. Details: `docs/design/`.

## Usage

| Recipe | What it does |
|---|---|
| `just app-build` / `just app-run [project.astrostack]` | Assemble `apps/macos/.build/AstroStack.app` (ad-hoc signed) / build and open it |
| `just doctor` | Host readiness: toolchain, Metal Toolchain, swiftlint, Siril/GraXpert/StarNet, data folders |
| `just test` / `just test-unit` / `just test-live` | Whole suite / everything but the `Live…` suites / only the live suites (host tools + fixtures) |
| `just lint` / `just fmt` | `swift format lint --strict` + `swiftlint --strict` / format in place |
| `just coverage` | Line coverage (lcov + summary) under `apps/macos/.build/coverage` |
| `just hygiene` | Repo gate: Swift only, no pixels, no data symlinks, no large blobs |
| `just check` / `just ci` | The pre-push gate / exactly what CI runs |

## Development

`just check` before every PR (the pre-push hook from `just hooks` runs it); CI runs `just ci` on a
`macos-26` runner for pull requests only, because macOS minutes bill at 10×. Live tests (Siril,
GraXpert, StarNet, images under `~/Documents/astro/fixtures`) self-skip on CI and run on the
developer's Mac. Conventions in `conventions/`; the reasoning behind every gate and the decisions
taken for the Swift port (concurrency model, Metal 3, GRDB, swift-subprocess, oracles) in
`docs/engineering/swift-quality-playbook.md`.

## Name

Kappa-sigma clipping is the outlier rejection at the heart of every image stack.

## License

MIT — see `LICENSE`.
