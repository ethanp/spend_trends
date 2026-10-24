-- Sync projection_settings: this database's powersync publication lists its
-- tables explicitly, so new tables must be added (runs as the publication
-- owner).

ALTER PUBLICATION powersync ADD TABLE projection_settings;
