-- Life events gain a kind (milestone, job, home, childBirth) and that kind's
-- projection details as JSON. Planned children move here from the
-- projection assumptions, and the assumptions that home and job events now
-- carry are dropped.

ALTER TABLE life_events
    ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'milestone'
        CHECK (kind IN ('milestone', 'job', 'home', 'childBirth'));
ALTER TABLE life_events ADD COLUMN IF NOT EXISTS details_json TEXT;

INSERT INTO life_events (id, title, started_on, ended_on, note, kind)
SELECT
    gen_random_uuid()::text,
    'Child born',
    birth_millis,
    birth_millis,
    'Planned; moved from the projection’s child birth years.',
    'childBirth'
FROM (
    SELECT (extract(epoch FROM (make_date(birth_year::int, 7, 1)::timestamp
        AT TIME ZONE 'America/Chicago')) * 1000)::bigint AS birth_millis
    FROM projection_settings,
        jsonb_array_elements_text(settings_json::jsonb -> 'childBirthYears')
            AS birth_year
    WHERE id = 'retirement_projection'
) AS planned_children;

UPDATE projection_settings
SET settings_json = (
    settings_json::jsonb
        - 'childBirthYears'
        - 'mortgageRatePercent'
        - 'housingAfterPayoffMonthlyDollars'
        - 'takeHomeOverrideAnnualDollars'
)::text
WHERE id = 'retirement_projection';
