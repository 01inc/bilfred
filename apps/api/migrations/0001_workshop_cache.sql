CREATE TABLE workshop_registry_snapshots (
    id uuid PRIMARY KEY,
    retrieved_at timestamptz NOT NULL,
    source_url text NOT NULL,
    content_sha256 text NOT NULL,
    national_count integer NOT NULL CHECK (national_count > 0),
    oslo_count integer NOT NULL CHECK (oslo_count >= 0)
);

CREATE TABLE workshops (
    approval_id text PRIMARY KEY,
    organization_number text NOT NULL,
    parent_organization_number text,
    name text NOT NULL,
    branch_name text,
    address text NOT NULL,
    postcode text NOT NULL,
    city text NOT NULL,
    website_url text,
    phone text,
    approvals text[] NOT NULL,
    county_code text,
    active boolean NOT NULL DEFAULT true,
    source_retrieved_at timestamptz NOT NULL,
    snapshot_id uuid NOT NULL REFERENCES workshop_registry_snapshots(id),
    raw jsonb NOT NULL
);
CREATE INDEX workshops_county_idx ON workshops (county_code) WHERE active;
CREATE INDEX workshops_approvals_idx ON workshops USING gin (approvals);

CREATE TABLE workshop_enrichment_runs (
    run_key text PRIMARY KEY,
    approval_id text NOT NULL REFERENCES workshops(approval_id),
    service text NOT NULL,
    retrieved_at timestamptz NOT NULL,
    status text NOT NULL,
    raw jsonb NOT NULL
);

CREATE TABLE workshop_enrichments (
    approval_id text NOT NULL REFERENCES workshops(approval_id),
    service text NOT NULL,
    price_nok numeric(10,2) CHECK (price_nok >= 0),
    price_type text CHECK (price_type IN ('fixed', 'from')),
    price_source_url text,
    price_source_kind text,
    price_retrieved_at timestamptz,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    review_count integer CHECK (review_count >= 0),
    rating_source_url text,
    rating_retrieved_at timestamptz,
    public_customers boolean,
    last_attempt_at timestamptz NOT NULL,
    last_attempt_status text NOT NULL,
    PRIMARY KEY (approval_id, service),
    CHECK (price_nok IS NULL OR (price_type IS NOT NULL AND price_source_url IS NOT NULL AND price_retrieved_at IS NOT NULL)),
    CHECK (rating IS NULL OR (rating_source_url IS NOT NULL AND rating_retrieved_at IS NOT NULL))
);
