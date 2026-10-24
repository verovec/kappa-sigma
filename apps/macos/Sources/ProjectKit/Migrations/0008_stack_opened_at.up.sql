-- 0008_stack_opened_at: when the Studio last opened a stack (card 0114). The Storage section
-- shows it, and the retention policy counts a stack's age from its last use (opened, else
-- created): a stack being worked on is never offered for deletion. NULL = never opened.
ALTER TABLE stacks ADD COLUMN opened_at INTEGER;
-- Before 0008 nobody recorded openings: a stack worked on was opened at its last Studio step. One
-- never worked on may still have been looked at: its age restarts at the upgrade (updated_at, the
-- row is written here), and it still reads « never opened ».
UPDATE stacks SET opened_at = (
  SELECT MAX(h.created_at) FROM history_steps h JOIN images i ON h.image_id = i.id
  WHERE i.stack_id = stacks.id);
UPDATE stacks SET updated_at = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
WHERE opened_at IS NULL;
