-- The housing and job chains become life events, so each home and job is
-- entered once. Housing stays become residence events (homes with cost
-- details are home events already), job stays become job events, and each
-- stay ends the day before the next one in its chain starts. A stay that
-- already has an event of its lane starting the same day is that event.

ALTER TABLE life_events DROP CONSTRAINT IF EXISTS life_events_kind_check;
ALTER TABLE life_events ADD CONSTRAINT life_events_kind_check
    CHECK (kind IN ('milestone', 'job', 'home', 'residence', 'childBirth'));

CREATE FUNCTION pg_temp.chicago_day(millis BIGINT) RETURNS DATE
LANGUAGE sql IMMUTABLE AS $$
    SELECT (to_timestamp(millis / 1000.0) AT TIME ZONE 'America/Chicago')::date
$$;

CREATE FUNCTION pg_temp.chicago_midnight_millis(day DATE) RETURNS BIGINT
LANGUAGE sql IMMUTABLE AS $$
    SELECT (extract(epoch FROM (day::timestamp AT TIME ZONE 'America/Chicago'))
        * 1000)::bigint
$$;

INSERT INTO life_events (id, title, started_on, ended_on, note, kind)
SELECT
    chained.id,
    chained.label,
    chained.started_on,
    CASE WHEN chained.next_started_on IS NULL THEN NULL
        ELSE pg_temp.chicago_midnight_millis(
            pg_temp.chicago_day(chained.next_started_on) - 1)
    END,
    chained.note,
    chained.kind
FROM (
    SELECT id, label, started_on, note, 'residence' AS kind,
        lead(started_on) OVER (ORDER BY started_on) AS next_started_on
    FROM housing_stays
    UNION ALL
    SELECT id, label, started_on, note, 'job' AS kind,
        lead(started_on) OVER (ORDER BY started_on) AS next_started_on
    FROM job_stays
) AS chained
WHERE NOT EXISTS (
    SELECT 1 FROM life_events
    WHERE pg_temp.chicago_day(life_events.started_on)
            = pg_temp.chicago_day(chained.started_on)
        AND CASE chained.kind
            WHEN 'residence' THEN life_events.kind IN ('home', 'residence')
            ELSE life_events.kind = 'job'
        END
);

DROP TABLE housing_stays;
DROP TABLE job_stays;
