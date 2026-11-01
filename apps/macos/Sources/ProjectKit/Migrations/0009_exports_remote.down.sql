-- Undoes 0009_exports_remote: back to 0006's table. A row without a folder (S3 only) has no
-- 0006 shape and is dropped; the others keep their ids.
CREATE TABLE exports_old (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  stack_id      INTEGER NOT NULL REFERENCES stacks (id) ON DELETE CASCADE,
  image_id      INTEGER NOT NULL REFERENCES images (id) ON DELETE CASCADE,
  head_step_id  INTEGER REFERENCES history_steps (id) ON DELETE SET NULL,
  folder        TEXT    NOT NULL,
  settings_json TEXT    NOT NULL DEFAULT '{}',
  files_json    TEXT    NOT NULL DEFAULT '[]',
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
INSERT INTO exports_old (id, stack_id, image_id, head_step_id, folder, settings_json, files_json,
  created_at, updated_at)
SELECT id, stack_id, image_id, head_step_id, folder, settings_json, files_json, created_at,
  updated_at
FROM exports WHERE folder IS NOT NULL;
DROP TABLE exports;
ALTER TABLE exports_old RENAME TO exports;
CREATE INDEX exports_stack_id ON exports (stack_id);
CREATE INDEX exports_image_id ON exports (image_id);
CREATE INDEX exports_head_step_id ON exports (head_step_id);
