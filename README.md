# Kappa-Sigma

Native macOS app for deep-sky astrophotography: stack your captures with Siril, then finish them in a
PixInsight-like Studio with real-time Metal previews — every setting visible, explained and yours.

**Status: work in progress (2026-10-20).** Nothing runs yet. This repository holds the design
(`docs/design/astrostack-macos.md`), the conventions and the build/test gates; the Swift packages
arrive with the first roadmap card. The previous web engine (Go) lives in the sibling repo
`stacking-astro` and is only read as a reference while its rules are ported to Swift.

## Quickstart

```sh
just setup      # swiftlint + pre-push hook, then a host check (`just doctor`)
just app-build  # build the Swift packages (once apps/macos exists)
just check      # hygiene + lint + build + full suite — the pre-push gate
```

## Prerequisites (macOS host)

- Xcode 26 with the Metal Toolchain component (`xcodebuild -downloadComponent metalToolchain`),
  `just`, `swiftlint` (`just setup` installs it; `swift format` ships with the toolchain)
- Siril 1.4.x (`/Applications/Siril.app`), GraXpert, StarNet2 (your own install — never bundled)
- Your data in `~/Documents/astro/{captures,runs,library}` — read-only for the app, never in a repo

## Architecture

Swift 6 only. Modules (SwiftPM, `apps/macos`): `ImageKit` (FITS, planes, pyramid), `RenderKit`
(Metal viewer and shaders), `ProcessKit` (processes, history, recipes), `ProjectKit` (SQLite project),
`StackKit` (preprocessing: inspect, calibration library, Siril driver, grading, stacking), `HelpKit`.
Siril, GraXpert and StarNet are host tools driven by `StackKit`. Details: `docs/design/`.

## Usage

| Recipe | What it does |
|---|---|
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
