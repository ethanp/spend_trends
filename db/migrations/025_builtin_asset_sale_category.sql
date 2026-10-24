-- Asset sale is a built-in flow category: one-time proceeds (a house sale and
-- its mortgage payoff at closing) that count as neither income nor spending.
-- Net worth plots them as lump sums.

INSERT INTO categories (id, name, sort_order, archived, color_token)
VALUES ('cat_asset_sale', 'Asset sale', 1003, 0, NULL)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  sort_order = EXCLUDED.sort_order,
  archived = 0,
  group_id = NULL,
  conscious_spending_area = NULL;

-- The closing wire that paid off a sold home's mortgage was filed as
-- Investments, which counted the sale as income.
UPDATE transactions
SET user_category_id = 'cat_asset_sale'
WHERE raw_description LIKE 'Payoff, Wire%'
  AND coalesce(user_category_id, suggested_category_id) = 'cat_investments';
