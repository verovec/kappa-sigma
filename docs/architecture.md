# Architecture

Kappa-Sigma (the app is called AstroStack) is a single SwiftPM package, `apps/macos/Package.swift`,
written in Swift 6 only: SwiftUI and AppKit for the interface, Metal for every real-time preview,
Accelerate for CPU math, SQLite through GRDB for the project database. There is no server, no
helper binary and no second language. The full design, with the decisions behind it, is
[`design/astrostack-macos.md`](design/astrostack-macos.md).

## Modules

| Module | Role | Notes |
|--------|------|-------|
| `ImageKit` | FITS float32 reader and writer, planar image model, mip pyramid | [README](../apps/macos/Sources/ImageKit/README.md) |
| `RenderKit` | Metal viewer (zoom, pan, display stretch, histogram, compare), design system and shared components | [README](../apps/macos/Sources/RenderKit/README.md) |
| `ProcessKit` | Finishing processes (stretch, levels, curves, colour, emission screens, HDR, denoise, geometry, background, solve, star layer), parameter schema, history, pipelines, profiles | [README](../apps/macos/Sources/ProcessKit/README.md) |
| `ProjectKit` | The `.astrostack` package and its `project.db` (schema, migrations, typed store) | [README](../apps/macos/Sources/ProjectKit/README.md), [schema](../apps/macos/Sources/ProjectKit/SCHEMA.md) |
| `StackKit` | Preprocessing: frame inspection, calibration library, Siril driver, grading, stacking, multi-night lanes | [README](../apps/macos/Sources/StackKit/README.md) |
| `HelpKit` | Help cards and the fr/en glossary | [README](../apps/macos/Sources/HelpKit/README.md) |
| `StringCatalog` | Compiles and gates the fr/en string catalogs at build time | [README](../apps/macos/Sources/StringCatalog/README.md) |
| `CatalogTool` | The build-tool executable `CatalogPlugin` runs to compile the catalogs | |
| `AstroStackApp` | The executable: document lifecycle (AppKit), windows and screens (SwiftUI) | |

Module boundaries are pinned by a test in every test target (`Tests/TestSupport/BoundaryRules.swift`):
a kit never imports the app, and only `RenderKit` and the app import a UI framework.

## Host tools

The app drives tools installed on the Mac. It never bundles them and never falls back to another
algorithm when one is missing: the process is greyed with an install card instead.

| Tool | Used for | Version |
|------|----------|---------|
| [Siril](https://siril.org) | Calibration, registration, stacking (named-pipe session, script fallback); plate solving, PCC/SPCC, background extraction | 1.4.x |
| [GraXpert](https://www.graxpert.com) | Background extraction | 3.x |
| StarNet2 | Star removal for the star layer | your own install |

Byte identity with the legacy pipeline holds because Siril does the pixel math: the same script on
the same frame selection gives the same master. Each Swift port is pinned by a recorded oracle
(emitted scripts, frame selections, master checksums, reference renders).

## Data

Captures, calibration masters and test fixtures live outside every repository and are read only:

| Folder | Holds |
|--------|-------|
| `~/Documents/astro/captures/<Target>/` | Raw capture nights |
| `~/Documents/astro/library/` | Calibration masters (bias, darks, flats) |
| `~/Documents/astro/runs/<Target>/` | Results of the legacy engine, openable as project sources |
| `~/Documents/astro/fixtures/` | Image fixtures for the live tests |
| `~/AstroStack/Projects/<Target>.astrostack/` | Projects written by the app |

Nothing pixel-shaped is committed: fixtures in the repository are text (JSON, Siril scripts,
checksums). The only images in the repository are the README artwork in `docs/assets/`.
