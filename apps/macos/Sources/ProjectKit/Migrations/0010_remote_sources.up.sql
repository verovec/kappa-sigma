-- 0010_remote_sources: a source may be an S3 prefix scanned in place (card 0168). `kind` gains
-- `remote_night` and the row says which Settings connection (0150) reads it, from which bucket and
-- prefix; `path` is the virtual `s3://bucket/prefix` the scan walks, never a file path. SQLite
-- cannot alter a CHECK, so the table is rebuilt with its rows, ids and `profile_id` kept.
--
-- `sources` is a parent table: `stack_sources` points at it ON DELETE RESTRICT, and SQLite refuses
-- to drop a parent whose children hold rows (RESTRICT is immediate — `defer_foreign_keys` does not
-- lift it). The links are therefore set aside and put back here, inside the migration, rather than
-- by running the migrator with foreign keys off: 0007's down relies on ON DELETE CASCADE firing,
-- which a global `PRAGMA foreign_keys = OFF` would silently stop.
CREATE TABLE stack_sources_0010 AS SELECT * FROM stack_sources;
DELETE FROM stack_sources;

CREATE TABLE sources_new (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  kind          TEXT    NOT NULL CHECK (kind IN ('night', 'legacy_run', 'remote_night')),
  path          TEXT    NOT NULL,
  read_only     INTEGER NOT NULL DEFAULT 1 CHECK (read_only IN (0, 1)),
  profile_id    TEXT,
  connection_id TEXT,
  bucket        TEXT,
  prefix        TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE (kind, path)
);
INSERT INTO sources_new (id, kind, path, read_only, profile_id, created_at, updated_at)
SELECT id, kind, path, read_only, profile_id, created_at, updated_at FROM sources;
DROP TABLE sources;
ALTER TABLE sources_new RENAME TO sources;

INSERT INTO stack_sources (stack_id, source_id, created_at, updated_at)
SELECT stack_id, source_id, created_at, updated_at FROM stack_sources_0010;
DROP TABLE stack_sources_0010;

-- What the last scan of a remote source already read, by its virtual path: one JSON body per
-- source (keys, ETags, header cards, side files), so a rescan reads only what changed. Derived
-- data with no schema of its own — a cached field never costs a migration; the body is StackKit's
-- `RemoteScanCache`, kept like `pipelines` and `user_profiles` keep theirs.
CREATE TABLE remote_scans (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL UNIQUE,
  body_json  TEXT    NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
