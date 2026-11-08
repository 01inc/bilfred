-- Durable provider run IDs survive API restarts and client disconnects.
CREATE TABLE maintenance_jobs (
    id uuid PRIMARY KEY,
    fingerprint text NOT NULL UNIQUE,
    status text NOT NULL CHECK(status IN ('creating', 'running', 'completed', 'failed')),
    provider_run_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_polled_at timestamptz,
    completed_at timestamptz,
    error_code text
);
CREATE INDEX maintenance_jobs_created_idx ON maintenance_jobs(created_at);
