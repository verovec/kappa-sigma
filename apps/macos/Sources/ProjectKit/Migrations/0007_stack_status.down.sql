-- Undoes 0007_stack_status: a paused run has no bundle, so it cannot stay a stack.
DELETE FROM stacks WHERE status = 'paused';
DROP INDEX stacks_status;
ALTER TABLE stacks DROP COLUMN checkpoint_json;
ALTER TABLE stacks DROP COLUMN status;
