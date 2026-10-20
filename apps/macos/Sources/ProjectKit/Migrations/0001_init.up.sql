-- 0001_init: the project schema (card 0068). Never edited after merge: later cards add 0002+.
-- House rules (conventions/database-conventions.md): surrogate id, snake_case plural tables,
-- created_at / updated_at as int64 Unix milliseconds set by ProjectStore, every FK indexed.

-- Where pixels come from: an imported capture night or a legacy run, referenced by path,
-- never copied or written (R7).
CREATE TABLE sources (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  kind        TEXT    NOT NULL CHECK (kind IN ('night', 'legacy_run')),
  path        TEXT    NOT NULL,
  read_only   INTEGER NOT NULL DEFAULT 1 CHECK (read_only IN (0, 1)),
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (kind, path)
);

-- A bundle produced by preprocessing (0057) or read from a legacy run (0043).
CREATE TABLE stacks (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  bundle_path  TEXT    NOT NULL,
  params_json  TEXT    NOT NULL DEFAULT '{}',
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE stack_sources (
  stack_id    INTEGER NOT NULL REFERENCES stacks (id) ON DELETE CASCADE,
  source_id   INTEGER NOT NULL REFERENCES sources (id) ON DELETE RESTRICT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (stack_id, source_id)
);
CREATE INDEX stack_sources_source_id ON stack_sources (source_id);

-- An image of a stack (one role: rgb, L, Ha…) and the head of its non-destructive history.
CREATE TABLE images (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  stack_id      INTEGER NOT NULL REFERENCES stacks (id) ON DELETE CASCADE,
  role          TEXT    NOT NULL,
  head_step_id  INTEGER REFERENCES history_steps (id) ON DELETE SET NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX images_stack_id ON images (stack_id);
CREATE INDEX images_head_step_id ON images (head_step_id);

-- One applied process (0049): its parameters, and the file it wrote (counted by the disk budget).
CREATE TABLE history_steps (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  image_id      INTEGER NOT NULL REFERENCES images (id) ON DELETE CASCADE,
  ordinal       INTEGER NOT NULL CHECK (ordinal > 0),
  process_id    TEXT    NOT NULL,
  params_json   TEXT    NOT NULL DEFAULT '{}',
  output_path   TEXT,
  output_bytes  INTEGER NOT NULL DEFAULT 0 CHECK (output_bytes >= 0),
  content_hash  TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE (image_id, ordinal)
);

-- A named point of an image's history; the step it points to cannot be deleted under it.
CREATE TABLE snapshots (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  image_id    INTEGER NOT NULL REFERENCES images (id) ON DELETE CASCADE,
  step_id     INTEGER NOT NULL REFERENCES history_steps (id) ON DELETE RESTRICT,
  name        TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (image_id, name)
);
CREATE INDEX snapshots_step_id ON snapshots (step_id);

-- Recipes and pipelines (0059), user profiles (0060): named JSON documents for now; those cards
-- add the columns they query.
CREATE TABLE recipes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL UNIQUE,
  body_json   TEXT    NOT NULL DEFAULT '{}',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE pipelines (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL UNIQUE,
  body_json   TEXT    NOT NULL DEFAULT '{}',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE user_profiles (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL UNIQUE,
  body_json   TEXT    NOT NULL DEFAULT '{}',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
