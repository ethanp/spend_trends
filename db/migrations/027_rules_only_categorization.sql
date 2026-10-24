-- Categories come only from rules. Each transaction carries the category its
-- best-matching rule assigns (category_id) and that rule (category_rule_id);
-- hand locks and import suggestions are gone. Rules carry a note with their
-- reasoning, and specificity (account scope, exact match, pattern length)
-- replaces priority.

ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS category_id TEXT REFERENCES categories(id);

ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS category_rule_id TEXT;

-- Keep today's categories until rules are backfilled for them.
UPDATE transactions
SET category_id = coalesce(user_category_id, suggested_category_id);

ALTER TABLE transactions DROP COLUMN IF EXISTS user_category_id;
ALTER TABLE transactions DROP COLUMN IF EXISTS suggested_category_id;

ALTER TABLE categorization_rules ADD COLUMN IF NOT EXISTS note TEXT;
ALTER TABLE categorization_rules DROP COLUMN IF EXISTS priority;
