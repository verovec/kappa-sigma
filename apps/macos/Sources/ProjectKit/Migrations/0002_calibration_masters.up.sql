-- 0002_calibration_masters: the index of the calibration library folder (card 0047).
-- The folder (~/Documents/astro/library) stays the truth: a reindex upserts every master file and
-- deletes the rows whose file is gone. Keys come from the master's file name; frame_count and
-- pool_hash from its .sig sidecar; width/height from its FITS header (the sensor guard).
CREATE TABLE calibration_masters (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  path          TEXT    NOT NULL UNIQUE,
  type          TEXT    NOT NULL CHECK (type IN ('BIAS', 'DARK', 'FLAT', 'DARKFLAT')),
  filter        TEXT    NOT NULL DEFAULT '',
  exposure_ms   INTEGER NOT NULL DEFAULT 0,
  gain          INTEGER NOT NULL DEFAULT 0,
  "offset"      INTEGER NOT NULL DEFAULT 0,
  bin           INTEGER NOT NULL DEFAULT 1,
  temp_milli_c  INTEGER NOT NULL DEFAULT 0,
  has_temp      INTEGER NOT NULL DEFAULT 0 CHECK (has_temp IN (0, 1)),
  session       TEXT    NOT NULL DEFAULT '',
  recipe        TEXT    NOT NULL DEFAULT '',
  frame_count   INTEGER NOT NULL DEFAULT 0 CHECK (frame_count >= 0),
  pool_hash     TEXT    NOT NULL DEFAULT '',
  width         INTEGER NOT NULL DEFAULT 0,
  height        INTEGER NOT NULL DEFAULT 0,
  file_bytes    INTEGER NOT NULL DEFAULT 0 CHECK (file_bytes >= 0),
  file_mtime_ms INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX calibration_masters_type_gain ON calibration_masters (type, gain, "offset", bin);
