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
  <img src="docs/assets/m31.jpg" width="900" alt="The Andromeda Galaxy, M 31, with M 32 and M 110">
  <br>
  <sub>M 31, the Andromeda Galaxy, with its companions M 32 and M 110.</sub>
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

A project is a `.astrostack` package (a SQLite database plus its images) for one target.
**New Project…** creates it, **Import Captures…** reads your capture folder (never writing to it),
then the sidebar walks you through six stages, in the order an astrophotographer works. Each stage
shows its state (to do, ready, needs a look, done) and you move between them freely: nothing jumps
ahead on its own.

| Stage | What you do there |
|-------|-------------------|
| **Data** | See your nights sorted by night, filter and frame type, with integration time and calibration coverage; add a night later and rescan; trim or delete stacks never exported. |
| **Calibration** | Match each light set to the masters of your library, night by night, every choice overridable; inspect a master's statistics and rebuild it. |
| **Review** | Grade every frame, blink through them, keep or reject, pin the registration reference; double-click a frame to open it in the viewer. |
| **Stacking** | Stack one or many nights through Siril, broadband and dual-band lanes side by side, with simple or advanced settings per lane. Follow the journal, pause, continue after a reopen, cancel; the scratch space is checked before the run and cleaned up after. |
| **Studio** | Finish the image with live GPU previews: stretch (MTF, GHS, arcsinh), levels, curves, saturation, sky desaturation, colour balance, emission screens, Hα / OIII line injection, HDR, denoise, crop, rotate and flip. Background extraction (GraXpert or Siril), plate solving and colour calibration (PCC or SPCC). Work on the combined image or each channel's branch, with masks, an undoable history per layer, profiles, and pipelines that replay on a new stack. |
| **Export** | Separate the stars with StarNet2 and write the deliverables, with the recipe that made them. |

Everywhere in the app:

- **Viewer:** FITS on the GPU with zoom, pan and full screen, auto or manual display stretch, a
  histogram that names the image it counts, pixel readout with RA/Dec, clipping overlay and
  before/after compare.
- **Sky objects:** a catalogue from Siril's lists, searchable by any alias and offered to the plate
  solver.
- **Help:** a card for every stage, process and setting that explains each default.
- **Keyboard:** full screen (⇧⌘F), zoom (⌘= / ⌘-), rotate and flip, the View panel (⌥⌘0), and one
  ⌘Z undoes a whole pipeline run.
- **Languages:** English and French.

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
