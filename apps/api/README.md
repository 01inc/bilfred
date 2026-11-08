# Bilfred API

FastAPI on Python 3.12, managed with `uv` and the committed lockfile.

From `apps/api`, with your local `DATABASE_URL` set in the environment:

```sh
uv sync --frozen
uv run ruff check bilfred tests
uv run python -m pytest -q
```

Integration tests create disposable schemas in the dedicated local Bilfred
PostgreSQL on port 5448. They refuse a different database endpoint. They exercise
ownership, simultaneous acceptance retries, immutable offers, simulated booking
changes, research planning and last-good vehicle caching.

For a fresh database, review the six files in `migrations/`, then run:

```sh
uv run python -m bilfred.db
uv run uvicorn bilfred.app:app --host 127.0.0.1 --port 8008 --no-access-log
```

A fresh database supports synthetic demo vehicles/options without imported data.
Live vehicle lookups additionally need `VEGVESEN_API_KEY`; research needs
`EXA_API_KEY`. No credentials, production datasets or private photograph are
included. The optional image endpoint returns 404 when the local photo is absent.

Review migrations before running `uv run python -m bilfred.db`. Migrations are
ordered, transactional and checksum-verified; the application runtime never runs
DDL. Private local database mapping lives in `.local/database.json` at repository
root. Cloud uses `DATABASE_URL` from Secret Manager and a restricted runtime role.

From repository root, `node scripts/run-local-api.mjs` loads local server-only
provider variables and serves port 8008. `pnpm verify:api <origin>` tests the
connected journey and writes a private receipt. It creates demo records, never
actual bookings or payments.

Maintenance research is cache-first. The server stores Exa run IDs before polling;
relaunch resumes the same run. New research is bounded to 20 jobs per day globally.
The official EU deadline is never supplied by the research model. Proposed dates,
manufacturer intervals, driver history and confirmed vehicle facts stay separate.

Workshop facts come from Statens vegvesen. Cached address coordinates come from
Kartverket's open address API (CC BY 4.0). The demo ranking weights reputation,
distance from the selected area and price at 50%, 30% and 20%. Published prices and
ratings are researched evidence, not provider-contracted offers.

All acceptance, payment-method and booking-change routes are demonstration-only.
An accepted offer remains immutable. `demo_bookings` stores its mutable requested
time and active/completed state with revision checks. No charge, availability
reservation or workshop confirmation is created.

## Waitlist

Set server-only `WAITLIST_API_KEY` to a separate random secret shared with the web
server. `POST /v1/waitlist` validates email, explicit consent, consent version and
an abuse-counter digest. Duplicate emails return the same response.
`POST /v1/waitlist/cleanup` uses the same protected key and should run daily to
remove expired signups and abuse counters. Migration 0006 adds these tables.
