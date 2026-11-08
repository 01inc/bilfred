-- A mutable demonstration booking sits beside the immutable accepted offer.
-- No payment authorization or fulfillment confirmation is represented here.
CREATE TABLE demo_bookings (
    id uuid PRIMARY KEY REFERENCES acceptances(id),
    installation_id uuid NOT NULL REFERENCES installations(id),
    appointment_at timestamptz,
    payment_method text CHECK(payment_method IN ('apple_pay', 'vipps')),
    state text NOT NULL DEFAULT 'active' CHECK(state IN ('active', 'completed')),
    revision integer NOT NULL DEFAULT 1 CHECK(revision >= 1),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX demo_bookings_installation_idx ON demo_bookings(installation_id, updated_at DESC);
INSERT INTO demo_bookings(id, installation_id)
SELECT id, installation_id FROM acceptances;
