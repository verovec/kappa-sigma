-- Undoes 0005_stack_object_scope exactly.
ALTER TABLE stacks DROP COLUMN scope_json;
ALTER TABLE stacks DROP COLUMN object;
