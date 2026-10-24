-- Assign categories to Ramit Sethi's four conscious-spending buckets.

ALTER TABLE categories
    ADD COLUMN IF NOT EXISTS conscious_spending_area TEXT CHECK (
        conscious_spending_area IS NULL OR
        conscious_spending_area IN ('fixedCosts', 'investments', 'savings', 'guiltFree')
    );

UPDATE categories
SET conscious_spending_area = 'fixedCosts'
WHERE id IN ('cat_housing', 'cat_utilities', 'cat_groceries', 'cat_health', 'cat_transport')
   OR lower(trim(name)) IN ('housing', 'utilities', 'groceries', 'health', 'transport');

UPDATE categories
SET conscious_spending_area = 'guiltFree'
WHERE id IN ('cat_dining', 'cat_entertainment', 'cat_shopping', 'cat_travel', 'cat_other')
   OR lower(trim(name)) IN ('dining', 'entertainment', 'shopping', 'travel', 'other', 'learning', 'nellis');
