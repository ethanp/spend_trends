-- Retirement projection assumptions (one row, JSON) synced across devices.

CREATE TABLE IF NOT EXISTS projection_settings (
    id TEXT PRIMARY KEY,
    settings_json TEXT NOT NULL
);
