-- What an account's money cost for tax: a brokerage's cost basis, or a
-- Roth's contributions and conversions (what comes back out tax-free).
-- NULL means unknown; the projection then assumes a share of the balance.

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS tax_basis_cents BIGINT;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS tax_basis_as_of BIGINT;
