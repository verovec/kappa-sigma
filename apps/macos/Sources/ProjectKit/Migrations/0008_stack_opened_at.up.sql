-- 0008_stack_opened_at: when the Studio last opened a stack (card 0114). The Storage section
-- shows it, and the retention policy counts a stack's age from its last use (opened, else
-- created): a stack being worked on is never offered for deletion. NULL = never opened.
ALTER TABLE stacks ADD COLUMN opened_at INTEGER;
-- A stack worked on before 0008 counts from its last Studio step: never « old » on upgrade.
UPDATE stacks SET opened_at = (
  SELECT MAX(h.created_at) FROM history_steps h JOIN images i ON h.image_id = i.id
  WHERE i.stack_id = stacks.id);
