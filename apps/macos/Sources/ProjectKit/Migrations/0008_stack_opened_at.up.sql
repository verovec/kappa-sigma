-- 0008_stack_opened_at: when the Studio last opened a stack (card 0114). The Storage section
-- shows it, and the retention policy counts a stack's age from its last use (opened, else
-- created): a stack being worked on is never offered for deletion. NULL = never opened.
ALTER TABLE stacks ADD COLUMN opened_at INTEGER;
