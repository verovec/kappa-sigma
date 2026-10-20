# Kappa-Sigma

Native macOS app for deep-sky astrophotography: stack your captures with Siril, then finish them in a
PixInsight-like Studio with real-time Metal previews — every setting visible, explained and yours.

**Status: work in progress (2026-10-20).** Nothing runs yet. This repository holds the design
(`docs/design/astrostack-macos.md`), the conventions and the build/test gates; the Swift packages
arrive with the first roadmap card. The previous web engine (Go) lives in the sibling repo
`stacking-astro` and is only read as a reference while its rules are ported to Swift.

## Quickstart

```sh
just            # list recipes
just app-build  # build the Swift packages (once apps/macos exists)
just check      # lint + tests — the pre-push gate
```

## Prerequisites (macOS host)

- Xcode 26 with the Metal Toolchain component, `just`, `swift-format`
- Siril 1.4.x (`/Applications/Siril.app`), GraXpert, StarNet2 (your own install — never bundled)
- Your data in `~/Documents/astro/{captures,runs,library}` — read-only for the app, never in a repo

## Architecture

Swift 6 only. Modules (SwiftPM, `apps/macos`): `ImageKit` (FITS, planes, pyramid), `RenderKit`
(Metal viewer and shaders), `ProcessKit` (processes, history, recipes), `ProjectKit` (SQLite project),
`StackKit` (preprocessing: inspect, calibration library, Siril driver, grading, stacking), `HelpKit`.
Siril, GraXpert and StarNet are host tools driven by `StackKit`. Details: `docs/design/`.

## Development

`just check` before every PR; CI runs `just ci` on a macOS runner. Conventions in `conventions/`.

## Name

Kappa-sigma clipping is the outlier rejection at the heart of every image stack.

## License

MIT — see `LICENSE`.
