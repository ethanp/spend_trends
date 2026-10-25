-- 529 plans get their own tax treatment: they pay college, not retirement.

ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_tax_treatment_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_tax_treatment_check
    CHECK (tax_treatment IN ('traditional', 'roth', 'college', 'taxable', 'excluded'));
