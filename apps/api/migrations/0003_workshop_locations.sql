-- Nullable official-address geocodes; failed lookups leave previous coordinates intact.
ALTER TABLE workshops ADD COLUMN latitude double precision CHECK (latitude BETWEEN -90 AND 90);
ALTER TABLE workshops ADD COLUMN longitude double precision CHECK (longitude BETWEEN -180 AND 180);
ALTER TABLE workshops ADD COLUMN location_source text;
ALTER TABLE workshops ADD COLUMN location_retrieved_at timestamptz;
ALTER TABLE workshops ADD CONSTRAINT workshop_coordinate_pair CHECK ((latitude IS NULL) = (longitude IS NULL));
