-- No savings-goals bucket: planned expenses come straight from paychecks, so
-- the conscious spending plan is fixed costs, investments, and guilt-free.

UPDATE categories
SET conscious_spending_area = NULL
WHERE conscious_spending_area = 'savings';

ALTER TABLE categories
DROP CONSTRAINT IF EXISTS categories_conscious_spending_area_check;

ALTER TABLE categories
ADD CONSTRAINT categories_conscious_spending_area_check CHECK (
    conscious_spending_area IS NULL OR
    conscious_spending_area IN ('fixedCosts', 'investments', 'guiltFree')
);
