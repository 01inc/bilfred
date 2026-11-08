CREATE TABLE installations (
    id uuid PRIMARY KEY,
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vehicle_cache (
    lookup_key text PRIMARY KEY,
    facts jsonb NOT NULL,
    source_retrieved_at timestamptz NOT NULL,
    last_attempt_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vehicles (
    id uuid PRIMARY KEY,
    installation_id uuid NOT NULL REFERENCES installations(id),
    lookup_key text NOT NULL REFERENCES vehicle_cache(lookup_key),
    demo boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (installation_id, lookup_key)
);

CREATE TABLE mileage_readings (
    id uuid PRIMARY KEY,
    vehicle_id uuid NOT NULL REFERENCES vehicles(id),
    km integer NOT NULL CHECK (km BETWEEN 0 AND 3000000),
    observed_on date NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX mileage_vehicle_latest_idx ON mileage_readings (vehicle_id, recorded_at DESC);

CREATE TABLE service_history (
    id uuid PRIMARY KEY,
    vehicle_id uuid NOT NULL REFERENCES vehicles(id),
    service text NOT NULL,
    completed_on date,
    km integer CHECK (km BETWEEN 0 AND 3000000),
    source text NOT NULL DEFAULT 'driver',
    recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE offers (
    id uuid PRIMARY KEY,
    installation_id uuid NOT NULL REFERENCES installations(id),
    vehicle_id uuid NOT NULL REFERENCES vehicles(id),
    version integer NOT NULL DEFAULT 1,
    mode text NOT NULL CHECK (mode IN ('demo')),
    snapshot jsonb NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE acceptances (
    id uuid PRIMARY KEY,
    installation_id uuid NOT NULL REFERENCES installations(id),
    offer_id uuid NOT NULL UNIQUE REFERENCES offers(id),
    offer_version integer NOT NULL,
    idempotency_key text NOT NULL,
    status text NOT NULL CHECK (status IN ('demo_accepted')),
    receipt jsonb NOT NULL,
    accepted_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (installation_id, idempotency_key)
);

CREATE TABLE maintenance_research (
    fingerprint text PRIMARY KEY,
    data jsonb NOT NULL,
    source_retrieved_at timestamptz NOT NULL
);
