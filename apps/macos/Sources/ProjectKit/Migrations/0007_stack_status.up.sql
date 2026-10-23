-- 0007_stack_status: a run paused after a lane (card 0097) keeps its stack row with status
-- 'paused' and its checkpoint (StackKit's PreprocessCheckpoint, JSON) so it survives closing the
-- project; Continue completes the row in place ('done', checkpoint NULL), Discard deletes it.
-- Every row written before 0097 is a finished stack.
ALTER TABLE stacks ADD COLUMN status TEXT NOT NULL DEFAULT 'done';
ALTER TABLE stacks ADD COLUMN checkpoint_json TEXT;
CREATE INDEX stacks_status ON stacks (status);
