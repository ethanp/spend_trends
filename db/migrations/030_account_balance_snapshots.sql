-- Recorded balances for manual accounts (institutions SimpleFIN cannot
-- reach, e.g. an HSA or a crypto app): each update is a dated snapshot, so
-- net worth history steps between real values.

CREATE TABLE IF NOT EXISTS account_balance_snapshots (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    balance_cents BIGINT NOT NULL,
    recorded_on BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS account_balance_snapshots_account_recorded
    ON account_balance_snapshots (account_id, recorded_on);

ALTER PUBLICATION powersync ADD TABLE account_balance_snapshots;
