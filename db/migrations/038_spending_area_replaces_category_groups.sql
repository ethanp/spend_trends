-- The conscious spending area is the one way categories are classified.
-- Category groups (Wants, Needs, Income) restated it, so they go. The
-- built-in Investments category fills the Investments area.

UPDATE categories
SET conscious_spending_area = 'investments'
WHERE id = 'cat_investments';

ALTER TABLE categories DROP COLUMN IF EXISTS group_id;

DROP TABLE IF EXISTS category_groups;
