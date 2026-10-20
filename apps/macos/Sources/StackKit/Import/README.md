# StackKit / Import

What the Import sheet shows before any run (card 0056): the scan of a capture, grouped by night,
and the calibration every light set would get, gaps included. The in-process successor of the
legacy `/api/inspect` + `/api/calib/preview` pair; it adds no heuristic of its own.

## Entry point

```swift
let plan = try ImportPlanner(builder: InventoryBuilder(timeZone: site))
  .plan(request, library: CalibrationLibrary.masters(in: store))
```

The scan reads every header (and pixels for undecided frames): call it off the main actor — the
app's `ImportPlanning.plan` is `@concurrent` and indexes the library first.

- `ImportRequest`: the folders and every user choice, encoded under the legacy `RunRequest` keys
  (`path`, `paths`, `filter_map`, `color_model`, `exclude_sets`, `filter_set_overrides`,
  `calib_exclude`, `force_calibration_frames`) with Go's `omitempty`; unknown values throw.
  `overrides` is the `InspectOverrides` the scan honours.
- `ImportPlan`: `inventory` (kept for the run), `nights` (lights and flats under their night, the
  shared darks/bias and undated frames under `""`, last), `calibration` (one `Channel` per light
  set, cells dark → flat → bias), `warnings`.
- A cell's `Status`: `library(path:frames:)`, `build(frames:)` (a master the capture's own frames
  would build), `excluded(proposed)` (unchecked by the user), `missing` (the channel's notes say
  why). `Channel.hasGap` is a `missing` cell only: an exclusion is a choice, not a gap.

## Rules

- R2: an excluded calibration is shown with what was proposed; a set excluded from the scan is
  gone from the plan (the scan drops it before grouping) — the app keeps its row to restore it.
- The plan runs `CalibrationPreview` twice (without and with `calib_exclude`) so an excluded role
  still names what it would have been; only a role the user unchecked is `excluded` — a `-opt`
  dark dropped with its bias is `missing`, with the matcher's note.
- `exclude_sets` ids are those of a scan BEFORE the filter map (`InventoryBuilder` excludes first):
  a set whose filter is a mapping target cannot be excluded by its shown id (the app disables it).
- Calibration choices (`calib_exclude`, `force_calibration_frames`) never need a rescan:
  `ImportPlanner.needsScan(from:to:)` says when one does, `ImportPlanner.replanned` rematches the
  kept `inventory` + `library`.

## Master disclosure (card 0071)

- `Cell.master`: the master applied (or the one excluded); `sourceSet(of:)` the capture set it
  stands for (`CalibrationMaster.satisfies`) — what "Rebuild" stacks.
- `alternatives(for:of:)`: every library master of the role, each run alone through the matcher:
  `chosen`, `matches` (loses on rank), `needsForce`, `otherSensor(note)`. The legacy request has
  no per-set pick: the user's choices are `calib_exclude` and the global
  `force_calibration_frames`.

## How to extend

- A new user choice: a field on `ImportRequest` under its legacy key (round-trip test in
  `ImportRequestTests`), projected into `InspectOverrides` or the calibration call — never a
  decision in the app.
- A new column: a field on `SetRow` read off `FrameSet`/`SetKey`, formatted in the app's
  `ImportFormat`.
