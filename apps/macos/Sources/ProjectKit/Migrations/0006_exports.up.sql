-- 0006_exports: what the Export stage wrote (card 0091) — one row per « Export »: the stack, the
-- image and the history head it exported, the folder, the ExportSettings it ran (JSON, owned by
-- ProcessKit) and the files written. Deliverables are not state: the files live outside the
-- package's stacks; this row is the record the journey reads (« Export » done) and lists.
CREATE TABLE exports (
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
CREATE INDEX exports_stack_id ON exports (stack_id);
CREATE INDEX exports_image_id ON exports (image_id);
CREATE INDEX exports_head_step_id ON exports (head_step_id);
