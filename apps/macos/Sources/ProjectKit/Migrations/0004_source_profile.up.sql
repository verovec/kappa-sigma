-- 0004_source_profile: the profile the user kept when importing a source (card 0060), by profile
-- id (a shipped profile, or the user's copy of that id); NULL when none was kept. A processing
-- choice, so it lives with what was imported, not in project_settings (UI state only).
ALTER TABLE sources ADD COLUMN profile_id TEXT;
