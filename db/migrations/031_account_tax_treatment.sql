-- Tax treatment for retirement projections, set per account on Banks.
-- NULL means the app infers it from the account's kind and name.

ALTER TABLE accounts ADD COLUMN IF NOT EXISTS tax_treatment TEXT
    CHECK (tax_treatment IN ('traditional', 'roth', 'taxable', 'excluded'));
