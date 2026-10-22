-- 0005_stack_object_scope: the object a stack was run for and the run scope (card 0095) — the
-- light sets it stacked, as JSON — so the stack picker lists « object · date · n lights » without
-- decoding params_json; '' / NULL for a stack recorded before 0095 (every light of its sources).
ALTER TABLE stacks ADD COLUMN object TEXT NOT NULL DEFAULT '';
ALTER TABLE stacks ADD COLUMN scope_json TEXT;
