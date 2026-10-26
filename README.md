<p align="center">
  <img src="docs/assets/logo.svg" width="120" height="120" alt="Kappa-Sigma logo">
</p>

<h1 align="center">Kappa-Sigma</h1>

<p align="center">
  <strong>Deep-sky astrophotography on the Mac, from the raw night to the finished image.</strong><br>
  Stack your captures with Siril, then finish them in a Studio with real-time Metal previews:
  every setting visible, explained and yours.
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> &middot;
  <a href="#how-it-works">How it works</a> &middot;
  <a href="#what-works-today">What works today</a> &middot;
  <a href="#tech-stack">Tech stack</a> &middot;
  <a href="#documentation">Documentation</a><br>
  English &middot; <a href="README.fr.md">Français</a>
</p>

<p align="center">
  <img alt="macOS 26" src="https://img.shields.io/badge/macOS-26-black?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&amp;logoColor=white">
  <img alt="Metal" src="https://img.shields.io/badge/GPU-Metal-8A8A8A">
  <img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue">
</p>

<p align="center">
  <img src="docs/assets/ngc7000.jpg" width="900" alt="The North America Nebula, NGC 7000, in Hα and OIII over RGB">
  <br>
  <sub>NGC 7000, the North America Nebula: Hα and OIII over RGB.</sub>
</p>

---

A night of deep-sky imaging leaves hundreds of raw frames, darks, flats and offsets. Turning them
into an image means calibrating, rejecting the bad frames, aligning, stacking, then stretching and
colouring a signal that is almost all noise. Existing tools either hide their decisions or bury
them in hundreds of panels.

**Kappa-Sigma** is a native macOS app that takes one target from the capture folder to the
finished image:

- **Reproducible.** Siril does the pixel math, so the same frames and settings give the same stack,
  to the byte.
- **Nothing hidden.** Every verdict (a rejected frame, a chosen master, a reference frame) is shown
  and can be overruled.
- **The value you see is the value applied.** No process measures the image to quietly change its
  own settings; measurements only ever fill a suggestion.
- **Your data stays yours.** Captures, masters and earlier results are read only; the app writes
  only inside its projects.

The name comes from kappa-sigma clipping, the outlier rejection at the heart of every image stack.

## Quick start

**Prerequisites:** a Mac on macOS 26 with the Command Line Tools (Swift 6.2 or later) and
[`just`](https://github.com/casey/just). Xcode is not required.

| Host tool | Needed for |
|-----------|-----------|
| [Siril](https://siril.org) 1.4 | Stacking, plate solving, colour calibration (required) |
| [GraXpert](https://graxpert.com) | Background extraction (optional, Siril can do it too) |
| [StarNet2](https://www.starnetastro.com) | Star separation at export (optional) |

A missing tool greys out the processes that need it, with an install card; nothing falls back
silently to another algorithm.

```bash
git clone https://github.com/verovec/kappa-sigma.git && cd kappa-sigma
just setup                              # install swiftlint and the pre-push hook, check the host
just app-build -c release               # build the optimized AstroStack.app
open -n apps/macos/.build/AstroStack.app
```

Use the release build for real nights: stacking and previews are much faster. For development,
`just app-run` builds a debug bundle at the same path and opens it (it replaces the release one,
and the other way round). `just doctor` reports the toolchain, the host tools and the data
folders from the terminal.

## How it works

The welcome window lists your recent projects and the host tools it found. **New Project…**
creates a project for one target; **Import Captures…** reads a capture folder (never writing to it)
and shows how each night will be calibrated. A project is a `.astrostack` package (a SQLite
database plus its images), and its sidebar follows the order an astrophotographer works in:

```
  Data          capture nights, lights per filter, integration time, calibration coverage
     |
  Calibration   the masters each light set uses, their statistics, the gaps
     |
  Review        per-frame metrics, blink, keep or reject, the reference frame
     |
  Stacking      the settings per lane and the Siril run, with its journal
     |
  Studio        stretch, emission lines, HDR, colour, stars, previewed live on the GPU
     |
  Export        star separation and the deliverables
```

Each stage shows its state (to do, ready, needs a look, done) and you move between them freely:
nothing jumps ahead on its own.

## What works today

The full journey runs end to end. It is validated on the author's M 31 (broadband and dual-band
nights) and IC 1848 captures against the legacy pipeline it replaces.

| Stage | What you can do |
|-------|-----------------|
| **Data** | Classify a capture folder by night, filter and frame type; add a night later and rescan; see, trim and delete stacks never exported. |
| **Calibration** | Match each light set to your master library by night, every verdict overridable; inspect and rebuild a master. |
| **Review** | Grade every frame, blink through them, keep or reject at a breakpoint, pin the registration reference; double-click a frame to open it in the viewer. |
| **Stacking** | Single- and multi-night runs through Siril, broadband and dual-band lanes, simple and advanced settings per lane, one run per object; progress, journal, pause, continue after a reopen, cancel. The scratch space is checked before a run starts, and what a dead run leaves is cleaned up. |
| **Studio** | Live GPU previews of stretch (MTF, GHS, arcsinh), levels, curves, saturation, sky desaturation, colour balance, emission screens, Hα / OIII line injection, HDR, denoise and geometry (crop, rotate, flip). Background extraction (GraXpert or Siril), plate solving and colour calibration (PCC or SPCC) through the host tools. Switch between the combined image and each channel's branch; one history per layer with undo; pipelines with breakpoints and replay; profiles; masks. |
| **Export** | Star separation with StarNet2 and the deliverable set, with the recipe that made it. |

Across the app:

- **Viewer:** FITS images on the GPU with zoom, pan, full screen, auto or manual display stretch, a
  histogram that says which image it counts, pixel readout with RA/Dec, clipping overlay and
  before/after compare.
- **Sky objects:** a catalogue built from Siril's lists, searchable by any alias, shown in the
  sidebar and offered to the plate solver.
- **Help:** a card for every stage, process and setting, explaining each default.
- **Keyboard:** full screen (⇧⌘F), zoom (⌘= / ⌘-), rotate and flip, show or hide the View panel
  (⌥⌘0), one ⌘Z for a whole pipeline run.
- **Languages:** English and French.

**Known limitations:** one-shot-colour cameras only (mono LRGB and narrowband palettes are
planned); no drizzle; no signed build yet, so the app is built from source.

## Tech stack

| Layer | Tech | Location |
|-------|------|----------|
| Interface | SwiftUI and AppKit (document-based app) | `apps/macos/Sources/AstroStackApp` |
| Real-time previews | Metal 3 kernels, each checked against a CPU oracle | `RenderKit`, `ProcessKit` |
| Image math | Accelerate (vDSP, vImage), planar float32 | `ImageKit`, `StackKit` |
| Preprocessing | Siril 1.4 driven over named pipes | `StackKit` |
| Project storage | SQLite through GRDB, versioned SQL migrations | `ProjectKit` |
| Tests | Swift Testing, recorded oracles, live suites on real captures | `apps/macos/Tests` |

Swift 6 only: no server, no helper binary, no second language. Details in
[Architecture](docs/architecture.md).

## Documentation

| Topic | Where |
|-------|-------|
| Modules, host tools, where your data lives | [`docs/architecture.md`](docs/architecture.md) |
| Toolchain, recipes, tests, CI, conventions | [`docs/development.md`](docs/development.md) |
| Product and architecture design | [`docs/design/astrostack-macos.md`](docs/design/astrostack-macos.md) |
| Quality gates and the decisions of the Swift port | [`docs/engineering/swift-quality-playbook.md`](docs/engineering/swift-quality-playbook.md) |
| Everything else | [`docs/`](docs/README.md) |

## Contributing

Issues and pull requests are welcome. Run `just check` before pushing: it is the same gate as CI
(hygiene, lint, app build, full test suite). The house conventions are in
[`conventions/`](conventions/), and [`docs/development.md`](docs/development.md) explains how tests,
oracles and the live suites work.

## License

[MIT](LICENSE) © 2026 Clément Verove
