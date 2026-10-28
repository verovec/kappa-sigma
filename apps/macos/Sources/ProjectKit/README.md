# ProjectKit

The AstroStack project on disk: a `.astrostack` package folder holding `project.db` (SQLite through
GRDB 7), and later `images/`, `recipes/`, `history/` (design §4.5). No UI, no AppKit.

## What exists (card 0040)

- `ProjectPackage` creates, opens, saves (WAL checkpoint), copies (Save As) and closes a package.
  `open` refuses a folder without `project.db` and any SQLite file AstroStack did not create
  (`PRAGMA application_id` = `ASTK`, read from the file header so a foreign file is never touched).
- A closed package is one self-contained `project.db`: `close` checkpoints and removes the `-wal` and
  `-shm` files GRDB's persistent WAL leaves behind.
- `ProjectPackageError` names the path in every case.
- One owner per project (card 0147): `open(at:owning:)` writes `project-owner.json` (the process's
  `ProcessStamp` — pid and start time — and a token per opening) and refuses with `openElsewhere(path:pid:)`
  while another running process holds it; a stale marker (a crash) is replaced and logged, this
  process's own is rewritten (a move, a Save As); `close()` removes it; a short opener
  (`owning: false`, the retention review) leaves it alone; `copy(to:)` never copies it;
  `readSummary` never reads it. `ProcessLiveness` is the one « does this pid still run » rule
  (StackKit's scratch owners call it). The name is not StackKit's scratch `owner.json`.

## The schema (card 0068)

- `project.db` follows `SCHEMA.md`: sources, stacks, images, history steps, snapshots, recipes,
  pipelines, user profiles. `create` and `open` migrate to the latest version.
- `ProjectStore` (`package.store`) is the typed access: plain value models (`ProjectSource`,
  `ProjectStack`, `ProjectImage`, `HistoryStep`, `ImageSnapshot`), parameterized SQL, timestamps
  in Unix ms from an injectable clock, and `diskBudgetBytes()` for the Studio.
- Migrations are SQL file pairs run by our `Migrator`, not GRDB's `DatabaseMigrator`, which cannot
  migrate down.
- A project moved in the Finder while open is reopened at its new place on the next Save
  (`ProjectDocument`): SQLite derives its WAL paths from the path it opened.

## Settings and summary (card 0076)

- `project_settings` (migration 0003): `setting(_:)` / `setSetting(_:to:)` keep small per-project
  values a window restores — the app's `JourneyStage.settingKey`, the journey stage last shown.
  ProjectKit knows no key: UI state only: a processing parameter belongs in history steps or recipes.
- `summary()` returns `ProjectSummary` (sources, stacks, images, history steps) in one read; the
  app derives the journey's stage states from it (`JourneyState`).

## Stacks (card 0057)

- Card 0095: `stacks.object` and `stacks.scope_json` (migration 0005) name what a run stacked —
  `addStack(…, object:scopeJSON:)` — so the app's stack picker lists « object · date · n lights »
  without decoding `params_json`; `columnNames(of:)` lets a migration test check a column round trip.

- A finished run of the Stacking stage is `addStack(bundlePath: "stacks/<run_id>", …)`: the
  path is relative to the package, `params_json` is the `ImportRequest` it ran (legacy wire keys),
  and the sources are the nights it read. Each bundle layer is one `images` row (role = layer id:
  `RGB`, `Ha`, `OIII`…), which is what makes the Studio stage ready.
- `stacks()` lists them oldest first. The Studio shows the last one, and the next run reuses its
  `params_json` overrides when the session has no newer import.
- Card 0097: `stacks.status` (`done` | `paused`) and `stacks.checkpoint_json` (migration 0007). A
  run paused after a lane is `addStack(…, status: .paused, checkpointJSON:)` with no images;
  `stacks()`, `latestStack()` and `summary().stacks` count finished stacks only, `pausedStacks()`
  lists the others. Continue ends in `completeStack(id:paramsJSON:imageRoles:)` (the same row,
  done), a second pause in `updatePausedStack`, Discard in `deletePausedStack` (a finished stack
  is refused: `notPaused`).

## Exports (card 0091)

- `exports` (migration 0006): `addExport(stackID:imageID:headStepID:folder:settingsJSON:files:)`
  records one « Export » — the image and history head written, the folder, ProcessKit's
  `ExportSettings` as JSON (never decoded here) and the file names; `exports(stackID:)` lists a
  stack's newest first. `summary().exports` counts them: the app's Export stage is « Done » from it.
- `summary(in:)` counts a table only if it exists: `readSummary(at:)` never migrates, so a package
  written before a migration reads 0 for the table it adds instead of failing.

## Storage and retention (card 0114)

- `deleteStack(id:packageFolder:openStackID:)` deletes a stack: snapshots of its images first
  (their step is `ON DELETE RESTRICT`), then the `stacks` row (images, history, exports, source
  links cascade), then its folder — only when the bundle path is exactly `stacks/<name>`, never
  anything else. The stack open in the Studio is refused (`ProjectStoreError.stackOpen`). Rows go
  before the folder: a folder that fails to go is a leftover 0113 lists, never a half-gone row.
- `stacks.opened_at` (migration 0008, backfilled from each stack's last history step; `readUsage` returns 0008's `applied_at` as `since`, a use of every stack) is set by
  `markStackOpened(id:)` when the Studio opens a stack; `exportCounts()` gives every exported
  stack's count. `closeKeepingWAL()` ends a short background write (the retention review) without
  removing `-wal`/`-shm`, which a window opening the project at that moment may hold.
- `RetentionPolicy` is pure: `candidates(_:exportCounts:protected:now:)` = finished, never
  exported, unused (opened, else created) for more than `days`, neither the project's newest nor
  protected; `delete(_:delete:)` deletes through the caller's closure, logs each, and returns what
  went. `ProjectPackage.readUsage(at:chosenKey:)` reads a closed project read-only (no migration,
  no checkpoint; `nil` before 0008): stacks, export counts, the Studio's chosen stack and the
  stacks kept from the launch sheet (`keepStacks`, `project_settings` `retention.kept`, so a moved
  project keeps the decision) — `StackUsage.protected`. The app owns the setting, the sizes
  (`LeftoverSweep.allocatedBytes`, never stored) and the launch review over the recent projects.

## Why `NSDocument` over the package, not SwiftUI `FileDocument`

`FileDocument`/`ReferenceFileDocument` save through `FileWrapper`: every save writes a new package
and swaps it in, which means copying `project.db` and every 22 Mpx FITS file each time. AstroStack
edits the package **in place** instead: the app's `ProjectDocument` (an `NSDocument`) overrides
`writeSafely(to:ofType:for:)` to checkpoint the open database on Save, and to call
`ProjectPackage.copy(to:)` only for Save As / Save To (playbook §7, decision 7). An untitled document
lives in a temporary package until its first save moves it; quitting deletes an unsaved one.

## How to extend

- A new table or column: add the next `Migrations/NNNN_name.{up,down}.sql` pair (never edit a
  merged one), update `SCHEMA.md`, add typed accessors to a `ProjectStore+<Topic>.swift` extension.
  `created_at`/`updated_at` as int64 ms (`conventions/database-conventions.md`); keep
  `application_id` as is.
- Anything stored next to `project.db` (images, recipes) must survive `copy(to:)`: it copies every
  item of the folder except the database files, which go through SQLite's online backup.
- Allowed dependencies: `ImageKit`, `GRDB` (`Tests/TestSupport/BoundaryRules.swift`).

## Pipelines (card 0059)

`savePipeline(named:json:)` / `pipeline(named:)` / `pipelineNames()` / `deletePipeline(named:)`
store ProcessKit's pipeline JSON in `pipelines.body_json` by unique name (an overwrite keeps the
row and `created_at`; an empty name is `ProjectStoreError.emptyName`). ProjectKit never decodes it:
`Pipeline.load` validates it against the registry when it is used.

