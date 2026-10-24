-- budgets schema for PowerSync (TEXT ids = client UUIDs)

CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    external_id TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    currency TEXT NOT NULL,
    balance_cents INTEGER NOT NULL,
    balance_as_of BIGINT,
    conn_id TEXT,
    conn_name TEXT,
    last_synced_at BIGINT,
    status TEXT NOT NULL,
    status_message TEXT,
    user_label TEXT,
    conn_user_label TEXT,
    account_kind TEXT,
    belongs_to_account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS category_groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    archived INTEGER NOT NULL DEFAULT 0,
    color_token TEXT,
    group_id TEXT REFERENCES category_groups(id),
    conscious_spending_area TEXT CHECK (
        conscious_spending_area IS NULL OR
        conscious_spending_area IN ('fixedCosts', 'investments', 'guiltFree')
    )
);

CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    external_id TEXT NOT NULL,
    posted_at BIGINT NOT NULL,
    amount_cents INTEGER NOT NULL,
    raw_description TEXT NOT NULL,
    normalized_merchant TEXT NOT NULL,
    pending INTEGER NOT NULL DEFAULT 0,
    category_id TEXT REFERENCES categories(id),
    category_rule_id TEXT,
    note TEXT,
    transaction_type TEXT,
    excluded INTEGER NOT NULL DEFAULT 0,
    recurring_series TEXT,
    imported_at BIGINT,
    UNIQUE(account_id, external_id)
);

CREATE TABLE IF NOT EXISTS categorization_rules (
    id TEXT PRIMARY KEY,
    match_type TEXT NOT NULL,
    pattern TEXT NOT NULL,
    category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
    note TEXT
);

CREATE TABLE IF NOT EXISTS life_events (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    started_on BIGINT NOT NULL,
    ended_on BIGINT,
    note TEXT
);

CREATE TABLE IF NOT EXISTS housing_stays (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    started_on BIGINT NOT NULL,
    note TEXT
);

CREATE TABLE IF NOT EXISTS job_stays (
    id TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    started_on BIGINT NOT NULL,
    note TEXT
);

CREATE TABLE IF NOT EXISTS sync_state (
    id TEXT PRIMARY KEY,
    key TEXT NOT NULL UNIQUE,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS simplefin_pulls (
    id TEXT PRIMARY KEY,
    started_at BIGINT NOT NULL,
    finished_at BIGINT,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    account_count INTEGER,
    transaction_count INTEGER,
    errors_json TEXT
);

CREATE TABLE IF NOT EXISTS simplefin_pull_accounts (
    id TEXT PRIMARY KEY,
    pull_id TEXT NOT NULL REFERENCES simplefin_pulls(id) ON DELETE CASCADE,
    account_id TEXT,
    account_external_id TEXT,
    conn_id TEXT,
    account_label TEXT NOT NULL,
    transaction_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS owned_assets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    asset_kind TEXT NOT NULL,
    note TEXT,
    sold_on BIGINT
);

CREATE TABLE IF NOT EXISTS owned_asset_valuations (
    id TEXT PRIMARY KEY,
    owned_asset_id TEXT NOT NULL REFERENCES owned_assets(id) ON DELETE CASCADE,
    value_cents INTEGER NOT NULL,
    valued_on BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS owned_asset_valuations_asset_valued
    ON owned_asset_valuations (owned_asset_id, valued_on DESC);

CREATE TABLE IF NOT EXISTS projection_settings (
    id TEXT PRIMARY KEY,
    settings_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS account_balance_snapshots (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    balance_cents BIGINT NOT NULL,
    recorded_on BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS account_balance_snapshots_account_recorded
    ON account_balance_snapshots (account_id, recorded_on);
