# StackKit / Legacy

Opens a finished legacy run (`~/Documents/astro/runs/<Object>/<run_id>/`, 32 runs, 132 GB)
**read-only** as a project source (card 0043). This is the input of every E12 parity test,
whose reference is run #78, `M_31/20261018_191749`.

## What exists

- `LegacyRunSource(folder:)` parses `run.json` (object, run id, per-channel `stacked_frames`) and
  `stages.json` (preset colour: mono/osc). Its layers come from one of two places:
  - the run's own `bundle.json` (root or `linear/`), when this app wrote it;
  - otherwise discovery (`LegacyLayerDiscovery`). `rgb_base.fits` (the post-headroom,
    post-crop linear base) is the `RGB` layer. Every other channel takes its best file by
    `LayerPrecedence` (`trim_ > combine_ > aligned_ > master_ > syn_`, shared with the 0048
    writer). A dual-band channel (`RGB-dualband`) is represented by its `syn_Ha`/`syn_OIII`
    lines, and those lines count its frames.
- `LegacyRunSource(stack:object:)` opens a stack this app ran into a project
  (`stacks/<run_id>/`, card 0057). Its `bundle.json` is the whole record: there is no `run.json`,
  so the target name comes from the project and frames are `nil`. Without a bundle it throws
  `LegacyRunError.noBundle`. The Studio stage shows the latest stack through it, with the same
  layer list and viewer as File › Open Run….
- Every layer must share one grid (headers only). Otherwise `LegacyRunError.mixedDimensions`
  lists each layer and its size.
- `LinearBundle.build(fromLegacyRun:)` is the bundle with stats measured by
  `BundleWriter.measure`: the writer's code, with nothing written.
- `record(in:)` stores the folder path only, read-only, in the project's `sources` table (0068).
  No layer is copied.
- App: File › Open Run… (⌘R, or `-openRun <folder>`) opens a Layers sidebar (role, file, size,
  frames). A chosen layer loads off the main actor into the 0042 viewer.

Files are only ever read (`FITSFile.read`, `Data(contentsOf:)`). `testReadOnlyDirOpens` opens a
`chmod a-w` copy, and the live test opens run #78 itself (RGB 76 frames, Hα/OIII 34,
5967×3763).
