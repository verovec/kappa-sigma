# project.db schema

The schema of a `.astrostack` package's `project.db`, at migration **0010_remote_sources**
(0001_init: card 0068; 0002: card 0047; 0003: card 0076; 0004: card 0060; 0005: card 0095;
0006: card 0091; 0007: card 0097; 0008: card 0114; 0009: card 0152; 0010: card 0168).
Source of truth: `Migrations/NNNN_name.{up,down}.sql`; this page is the map. Every table has
`id`, `created_at` and `updated_at`, the last two in int64 Unix milliseconds, except where noted.
`ProjectStore` writes the timestamps.

| Table | One row per | Columns besides id/timestamps | Keys and rules |
|---|---|---|---|
| `schema_migrations` | applied migration | `version` (PK), `name`, `applied_at` ms | written by the migrator only; no id/updated_at |
| `sources` | capture night, legacy run or S3 prefix, by path | `kind` (`night`, `legacy_run`, `remote_night` — 0010), `path`, `read_only`, `profile_id` (0004), `connection_id` (0010), `bucket` (0010), `prefix` (0010) | unique (kind, path); never written to (R7); `profile_id` = the profile kept at import, NULL for none; a `remote_night` (card 0168) has the virtual `s3://bucket/prefix` as its `path` — never canonicalised as a file — and names the Settings connection (0150) it is read through, its bucket and its prefix (no trailing `/`, `''` = the whole bucket); the three columns are NULL for a local source. 0010 rebuilds the table (SQLite cannot alter a CHECK) and sets the `stack_sources` links aside and back itself, because SQLite refuses to drop a parent whose children hold rows (`ON DELETE RESTRICT`) |
| `stacks` | bundle (0057, 0043) | `bundle_path`, `params_json`, `object` (0005), `scope_json` (0005), `status` (0007), `checkpoint_json` (0007), `opened_at` (0008) | `object` = the OBJECT the run stacked (`''` before 0095 or for every light), `scope_json` = the app's `RunScope` (its light-set ids), NULL before 0095; `status` = `done` (a bundle) or `paused` (card 0097: a run stopped after a lane, no images, `checkpoint_json` = StackKit's `PreprocessCheckpoint`); indexed on `status`; `opened_at` = ms when the Studio last opened it (NULL = never; 0008 backfills it from the stack's last history step; the retention policy also counts 0008's `applied_at` as a use), the retention age counts from the latest of `opened_at`, `updated_at` and 0008's `applied_at`; `ProjectStore.deleteStack` removes the row (snapshots first: RESTRICT), then `stacks/<name>` only |
| `stack_sources` | stack ↔ source link | `stack_id`, `source_id` | PK (stack_id, source_id); a source used by a stack cannot be deleted |
| `images` | image of a stack | `stack_id`, `role`, `head_step_id` | cascades with its stack; head set to NULL if its step goes |
| `history_steps` | applied process (0049) | `image_id`, `ordinal`, `process_id`, `params_json`, `output_path`, `output_bytes`, `content_hash` | unique (image_id, ordinal); the disk budget sums `output_bytes` of steps with a file |
| `snapshots` | named history point | `image_id`, `step_id`, `name` | unique (image_id, name); its step cannot be deleted under it |
| `recipes` | recipe (0059) | `name`, `body_json` | unique name; columns added by 0059 |
| `pipelines` | pipeline (0059) | `name`, `body_json` | unique name |
| `user_profiles` | user profile (0060) | `name`, `body_json` | unique name (the card's `profiles_user`, plural snake_case per the conventions) |
| `calibration_masters` | master file of the calibration library (0047) | `path`, `type` (`BIAS`, `DARK`, `FLAT`, `DARKFLAT`), `filter`, `exposure_ms`, `gain`, `offset`, `bin`, `temp_milli_c`, `has_temp`, `session`, `recipe`, `frame_count`, `pool_hash`, `width`, `height`, `file_bytes`, `file_mtime_ms` | unique path; an index of `~/Documents/astro/library` (the folder is the truth, `CalibrationLibrary.reindex` rebuilds it); indexed on (type, gain, offset, bin) |
| `exports` | « Export » of the Export stage (0091; S3 copy 0152, migration 0009) | `stack_id`, `image_id`, `head_step_id`, `folder` (NULL = S3 only), `settings_json`, `files_json`, `remote_url` (s3:// folder, NULL = no S3), `remote_status` (`none`/`done`/`failed`), `remote_error` (the service's words), `remote_connection` (the Settings connection id, for Resend) | cascades with its stack and image; `head_step_id` set to NULL if its step goes; `settings_json` = ProcessKit's `ExportSettings`, `files_json` = the file names written; the files live outside `stacks/` (deliverables are not state) |
| `remote_scans` | remote source's last scan (0168) | `name` (its virtual path), `body_json` | unique name; StackKit's `RemoteScanCache` (key -> ETag, size, header cards, side-file bytes — never the 200 000-value pixel runs, which are read again): a rescan reads no header it already has. Derived data — losing it costs reads, never correctness, and a new cached field never costs a migration |
| `project_settings` | per-project value a window restores (0076) | `key`, `value` | unique key; UI state only (`workspace.stage`), never a processing parameter |

Foreign keys are enforced (GRDB turns `PRAGMA foreign_keys` on) and every FK column is indexed.

## Changing the schema

Add `Migrations/NNNN_name.up.sql` and its `.down.sql` with the next version number; the down must
undo the up exactly (`ProjectStoreTests.testMigrateUpDown` pattern). Foreign keys stay **enforced** through the run,
so a migration that rebuilds a table other rows reference (the `sources` pattern of 0010) sets
those links aside and puts them back itself — `CREATE TABLE <child>_NNNN AS SELECT …`, `DELETE`,
rebuild, re-`INSERT`, `DROP`. Do not reach for `PRAGMA foreign_keys = OFF` in the migrator: it is
a no-op inside a transaction, and turning it off for the whole run silently stops the
`ON DELETE CASCADE` that other downs rely on (0007's). Pin a rebuild with a row some other table
points at and with `store.foreignKeyViolations()` empty after both directions (0010's test). Never edit a migration that
has been merged. `create` and `open` migrate to the latest version; opening a database written by
a newer build fails with `MigrationError.unknownVersion` instead of guessing.
