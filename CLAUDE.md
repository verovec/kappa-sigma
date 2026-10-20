# kappa-sigma — AstroStack 2 (native macOS, Swift only)

## Coding conventions (load on demand)

House conventions live in `./conventions/`. They are **not** auto-imported — READ the matching file
(Read tool) the first time a task touches that area, before writing or reviewing code there:

- Writing a **commit** message → `conventions/commit-conventions.md`
- **Swift / SwiftUI / Metal / concurrency** → `conventions/swift-conventions.md`
- **SQLite** schema, migrations, queries (ProjectKit) → `conventions/database-conventions.md`
- `just` recipes → `conventions/justfile-conventions.md`
- **README** → `conventions/readme-conventions.md`
- **Tests** (Swift Testing, oracles, live fixtures) → `conventions/testing-conventions.md`

A `UserPromptSubmit` hook auto-loads the convention(s) it detects from your prompt; read any it
missed. Edit the files in `./conventions/` to change the rules.

## Project rules (Kappa-Sigma)

**What this is.** AstroStack 2: a native macOS app for deep-sky astrophotography — stack captures
with Siril, then finish them in a PixInsight-like Studio with real-time Metal previews, every
setting visible, explained and adjustable. Design: `docs/design/astrostack-macos.md`. Roadmap:
epics **E10–E19**, cards 0040–0072 in `cards/` + `roadmap.md` (gitignored, local). Work it with
`/pick-card` (claims the next eligible card); `/new-card` writes cards. The Queue is ordered
**preprocessing-first**: the app stacks a night before the Studio exists.

**Language policy: Swift 6 only.** SwiftUI + AppKit for the UI, Metal for every real-time process,
Accelerate for CPU math, SwiftPM (`apps/macos/Package.swift`) as the source of truth. **No Go, no
Python, no cgo, no helper binary.** PO decision 2026-10-20 (`docs/design/…` §11.1): the hybrid
Swift + Go core was dropped; the preprocessing engine is **ported** to Swift as `StackKit` (E11).

**The legacy Go engine is a reference, never code.** It lives in the sibling repo
`../stacking-astro` (read-only here). Every `internal/<pkg>/<file>.go:NNN` pointer in a card means
`../stacking-astro/internal/...`. Read it to port a rule, translate its table-driven tests, pin the
port with a recorded oracle (0044: emitted Siril scripts, frame selections, master checksums,
reference renders). Byte-identity holds because **Siril does the pixel math**: same script + same
frame selection = same master. Never copy Go into this repo; never add a Go toolchain to CI.

**Data lives outside every repo (R7).** Captures `~/Documents/astro/captures/<Target>/…`, the 32
legacy runs `~/Documents/astro/runs/<Target>/<run>/`, calibration masters
`~/Documents/astro/library/`, test fixtures `~/Documents/astro/fixtures/` (see
`~/Documents/astro/README.md`). The app reads them **read-only** and keeps its projects in
`~/AstroStack/Projects/<Target>.astrostack/`. Nothing pixel-shaped is ever committed: fixtures in the
repo are text (JSON, `.ssf`, checksums); image fixtures are live-only and tests skip without them.
Never recreate `input/`/`output/`/`library/` or symlinks inside a repo.

**Host tools, invoked never bundled.** Siril 1.4.x (`siril-cli`, `-p` named pipes with `-s` script
fallback), GraXpert (`-cli`), StarNet2 (user install, no public licence). A missing tool greys the
process with an install card; **no silent fallback to another algorithm** (R2).

**R2 is structural.** No process measures the image to change its own settings; measurements are
displayed and may fill a *suggestion*. This holds in preprocessing too: every verdict (frame
rejection, master choice, reference frame) is visible and vetoable (0069–0071). Values applied =
values shown; untouched defaults stay byte-identical.

**Filters have ONE canonical list** (`L,R,G,B,Ha,OIII,SII`, aliases, display order, narrowband
flag) — one Swift source, pinned by a test. Never re-declare a filter list (the old fork had two
copies and SII was half-supported for months).

**Parity oracles.** Finishing processes (stretch, emission screens, HDR, colour, star layer) are
pinned against the PO's validated deliverable chain (astrocomp/hdrcomp/stardesat renders of run #78
`M31_v9style_hdr_HaPlus`), recorded once into `~/Documents/astro/fixtures/finish/` with a committed
manifest (0067). Tolerances are stated per test (mean |Δ| ≤ 1/255 unless the card says otherwise).

**Code graph (gitnexus).** Hooks keep a gitnexus index of this repo if the `gitnexus` binary is on
PATH (`just gitnexus-sync`). Swift support is not guaranteed — when `mcp__gitnexus__*` returns
nothing for Swift symbols, use Grep/Glob; for the legacy Go, query `repo:"astronomy"`.

**Running things.** `just` lists everything: `app-build`, `app-run`, `test`, `lint`, `check`, `ci`.
Live tests need the host tools and `~/Documents/astro/fixtures`; they self-skip on CI (macOS
runner, `just ci`). Real captures are processed only through the app or its live tests.
