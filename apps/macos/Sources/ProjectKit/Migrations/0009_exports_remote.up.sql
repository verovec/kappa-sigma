-- 0009_exports_remote: an export may also go to S3, or only there (card 0152). `folder` becomes
-- nullable (NULL = nothing kept on this Mac), `remote_url` is the s3:// folder (NULL = no S3),
-- `remote_status` says whether its upload is done or failed, `remote_error` keeps the service's
-- own words for a failed one (shown as is, R2), `remote_connection` the Settings connection (its
-- id) the copy went through: « Resend » uses it, never whichever the form shows now. SQLite cannot drop a NOT NULL: the table is
-- rebuilt, its rows and indexes kept.
CREATE TABLE exports_new (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  stack_id      INTEGER NOT NULL REFERENCES stacks (id) ON DELETE CASCADE,
  image_id      INTEGER NOT NULL REFERENCES images (id) ON DELETE CASCADE,
  head_step_id  INTEGER REFERENCES history_steps (id) ON DELETE SET NULL,
  folder        TEXT,
  settings_json TEXT    NOT NULL DEFAULT '{}',
  files_json    TEXT    NOT NULL DEFAULT '[]',
  remote_url    TEXT,
  remote_status TEXT    NOT NULL DEFAULT 'none' CHECK (remote_status IN ('none', 'done', 'failed')),
  remote_error  TEXT,
  remote_connection TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
INSERT INTO exports_new (id, stack_id, image_id, head_step_id, folder, settings_json, files_json,
  created_at, updated_at)
SELECT id, stack_id, image_id, head_step_id, folder, settings_json, files_json, created_at,
  updated_at
FROM exports;
DROP TABLE exports;
ALTER TABLE exports_new RENAME TO exports;
CREATE INDEX exports_stack_id ON exports (stack_id);
CREATE INDEX exports_image_id ON exports (image_id);
CREATE INDEX exports_head_step_id ON exports (head_step_id);
