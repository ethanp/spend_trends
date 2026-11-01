-- 034's "one-time" flag is renamed to what it means: spending left out of
-- lifestyle costs (Fixed costs plus Guilt-free), the FIRE baseline.
-- Furnishing or medical costs can be one-off and still be lifestyle costs.

ALTER TABLE categorization_rules
    RENAME COLUMN marks_one_time TO excludes_from_lifestyle_costs;

ALTER TABLE transactions
    RENAME COLUMN one_time TO excluded_from_lifestyle_costs;

-- A rename changes no rows, so clients would keep the value under the old
-- name and read the new column as empty. Rewrite every flagged row so sync
-- sends it again under the new name.
UPDATE categorization_rules
    SET excludes_from_lifestyle_costs = excludes_from_lifestyle_costs
    WHERE excludes_from_lifestyle_costs = 1;

UPDATE transactions
    SET excluded_from_lifestyle_costs = excluded_from_lifestyle_costs
    WHERE excluded_from_lifestyle_costs = 1;
