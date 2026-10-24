# project.db schema

The schema of a `.astrostack` package's `project.db`, at migration **0008_stack_opened_at**
(0001_init: card 0068; 0002: card 0047; 0003: card 0076; 0004: card 0060; 0005: card 0095;
0006: card 0091; 0007: card 0097; 0008: card 0114).
Source of truth: `Migrations/NNNN_name.{up,down}.sql`; this page is the map. Every table has
`id`, `created_at` and `updated_at`, the last two in int64 Unix milliseconds, except where noted.
`ProjectStore` writes the timestamps.

| Table | One row per | Columns besides id/timestamps | Keys and rules |
|---|---|---|---|
| `schema_migrations` | applied migration | `version` (PK), `name`, `applied_at` ms | written by the migrator only; no id/updated_at |
| `sources` | capture night or legacy run, by path | `kind` (`night`, `legacy_run`), `path`, `read_only`, `profile_id` (0004) | unique (kind, path); never written to (R7); `profile_id` = the profile kept at import, NULL for none |
| `stacks` | bundle (0057, 0043) | `bundle_path`, `params_json`, `object` (0005), `scope_json` (0005), `status` (0007), `checkpoint_json` (0007), `opened_at` (0008) | `object` = the OBJECT the run stacked (`''` before 0095 or for every light), `scope_json` = the app's `RunScope` (its light-set ids), NULL before 0095; `status` = `done` (a bundle) or `paused` (card 0097: a run stopped after a lane, no images, `checkpoint_json` = StackKit's `PreprocessCheckpoint`); indexed on `status`; `opened_at` = ms when the Studio last opened it (NULL = never; 0008 backfills it from the stack's last history step; the retention policy also counts 0008's `applied_at` as a use), the retention age counts from the latest of `opened_at`, `updated_at` and 0008's `applied_at`; `ProjectStore.deleteStack` removes the row (snapshots first: RESTRICT), then `stacks/<name>` only |
| `stack_sources` | stack ↔ source link | `stack_id`, `source_id` | PK (stack_id, source_id); a source used by a stack cannot be deleted |
| `images` | image of a stack | `stack_id`, `role`, `head_step_id` | cascades with its stack; head set to NULL if its step goes |
| `history_steps` | applied process (0049) | `image_id`, `ordinal`, `process_id`, `params_json`, `output_path`, `output_bytes`, `content_hash` | unique (image_id, ordinal); the disk budget sums `output_bytes` of steps with a file |
| `snapshots` | named history point | `image_id`, `step_id`, `name` | unique (image_id, name); its step cannot be deleted under it |
| `recipes` | recipe (0059) | `name`, `body_json` | unique name; columns added by 0059 |
| `pipelines` | pipeline (0059) | `name`, `body_json` | unique name |
| `user_profiles` | user profile (0060) | `name`, `body_json` | unique name (the card's `profiles_user`, plural snake_case per the conventions) |
| `calibration_masters` | master file of the calibration library (0047) | `path`, `type` (`BIAS`, `DARK`, `FLAT`, `DARKFLAT`), `filter`, `exposure_ms`, `gain`, `offset`, `bin`, `temp_milli_c`, `has_temp`, `session`, `recipe`, `frame_count`, `pool_hash`, `width`, `height`, `file_bytes`, `file_mtime_ms` | unique path; an index of `~/Documents/astro/library` (the folder is the truth, `CalibrationLibrary.reindex` rebuilds it); indexed on (type, gain, offset, bin) |
| `exports` | « Export » of the Export stage (0091) | `stack_id`, `image_id`, `head_step_id`, `folder`, `settings_json`, `files_json` | cascades with its stack and image; `head_step_id` set to NULL if its step goes; `settings_json` = ProcessKit's `ExportSettings`, `files_json` = the file names written; the files live outside `stacks/` (deliverables are not state) |
| `project_settings` | per-project value a window restores (0076) | `key`, `value` | unique key; UI state only (`workspace.stage`), never a processing parameter |

Foreign keys are enforced (GRDB turns `PRAGMA foreign_keys` on) and every FK column is indexed.

## Changing the schema

Add `Migrations/NNNN_name.up.sql` and its `.down.sql` with the next version number; the down must
undo the up exactly (`ProjectStoreTests.testMigrateUpDown` pattern). Never edit a migration that
has been merged. `create` and `open` migrate to the latest version; opening a database written by
a newer build fails with `MigrationError.unknownVersion` instead of guessing.
