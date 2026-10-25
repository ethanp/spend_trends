-- Daily net worth imported from an aggregator (Empower) for the years before
-- this app recorded balances itself. Trends uses these totals for every day
-- they cover, and its own account history after the last one.

CREATE TABLE IF NOT EXISTS imported_net_worth_days (
    id TEXT PRIMARY KEY,
    recorded_on BIGINT NOT NULL UNIQUE,
    net_worth_cents BIGINT NOT NULL
);

ALTER PUBLICATION powersync ADD TABLE imported_net_worth_days;
