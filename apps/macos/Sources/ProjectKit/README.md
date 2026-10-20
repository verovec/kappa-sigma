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
