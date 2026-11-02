-- Housing life events are owned or rental: `home` becomes `owned` and
-- `residence` becomes `rental`.

ALTER TABLE life_events DROP CONSTRAINT IF EXISTS life_events_kind_check;

UPDATE life_events SET kind = 'owned' WHERE kind = 'home';
UPDATE life_events SET kind = 'rental' WHERE kind = 'residence';

ALTER TABLE life_events ADD CONSTRAINT life_events_kind_check
    CHECK (kind IN ('milestone', 'job', 'owned', 'rental', 'childBirth'));
