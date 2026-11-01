-- One-time spending: a rule can mark what it categorizes as one-time (a move,
-- a closing, a second mortgage during a house overlap). The transaction keeps
-- its category; the flag is copied onto it with the category, so totals read
-- it without the rules.

ALTER TABLE categorization_rules
    ADD COLUMN IF NOT EXISTS marks_one_time INTEGER NOT NULL DEFAULT 0;

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS one_time INTEGER NOT NULL DEFAULT 0;
