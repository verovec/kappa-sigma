-- 0003_project_settings: small per-project values a window restores (card 0076), by key — the
-- journey stage last selected, for instance. Not a place for processing parameters: those live in
-- history steps and recipes, where they are versioned.
CREATE TABLE project_settings (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  key        TEXT    NOT NULL UNIQUE,
  value      TEXT    NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
