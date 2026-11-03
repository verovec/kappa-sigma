-- Undoes 0010_remote_sources: back to 0004's table (night | legacy_run). A remote night has no
-- 0004 shape: it goes, and so do the stack links that point at it (an older build cannot replay a
-- stack of remote frames; the stack itself stays, listed without that source — deleting it here
-- could hit the `snapshots → history_steps` RESTRICT and fail the whole downgrade). Local nights
-- and legacy runs keep their ids and `profile_id`.
--
-- As in the up, the links are set aside and put back around the rebuild: SQLite refuses to drop a
-- parent table while a child's rows point at it, and foreign keys stay enforced for the run.
DELETE FROM stack_sources
WHERE source_id IN (SELECT id FROM sources WHERE kind = 'remote_night');
DELETE FROM sources WHERE kind = 'remote_night';

CREATE TABLE stack_sources_0010 AS SELECT * FROM stack_sources;
DELETE FROM stack_sources;

CREATE TABLE sources_old (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT    NOT NULL CHECK (kind IN ('night', 'legacy_run')),
  path        TEXT    NOT NULL,
  read_only   INTEGER NOT NULL DEFAULT 1 CHECK (read_only IN (0, 1)),
  profile_id  TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (kind, path)
);
INSERT INTO sources_old (id, kind, path, read_only, profile_id, created_at, updated_at)
SELECT id, kind, path, read_only, profile_id, created_at, updated_at FROM sources;
DROP TABLE sources;
ALTER TABLE sources_old RENAME TO sources;

INSERT INTO stack_sources (stack_id, source_id, created_at, updated_at)
SELECT stack_id, source_id, created_at, updated_at FROM stack_sources_0010;
DROP TABLE stack_sources_0010;

DROP TABLE remote_scans;
