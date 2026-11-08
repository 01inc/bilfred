# Bilfred Build Plan

## Accepted Direction

Bilfred is a new repository and application. Strate is paused and preserved.
The current instruction supersedes the earlier offline-only infrastructure scope:
prepare a dedicated GCP project using the existing authorized account, a separate
Vercel project, and a future PostgreSQL-backed technical-vehicle lookup.

The first product interaction is registration entry -> fresh cache or Vegvesen ->
vehicle presentation. The user will provide the complete UI/UX vision after the
engineering handoff. Do not build the screens before that discussion.

## Verified State

- Separate local repository initialized with private handoff/credential exclusions.
- Private GitHub repository created for the source bootstrap.
- Fresh GCP project and dedicated inactive CLI configuration created, with billing
  linked to the existing dedicated account. Global defaults remain unchanged.
- A NOK 500 monthly alert budget covers Bilfred and retained Strate resources,
  with 50%, 80%, 100% and forecasted 100% thresholds, excluding credits.
  This is an alert budget, not a hard spending cap.
- Separate Vercel project created and locally linked: Next.js, Node 24.x,
  apps/web root. No frontend has been built or deployed, and Git auto-deployment
  is not connected while the application root does not yet exist.
- Public Vegvesen Swagger and OpenAPI endpoints return HTTP 200.
- Unauthenticated technical-vehicle endpoint returns HTTP 401. This establishes
  network and authentication-gateway reachability, not authenticated lookup success.
- One authenticated real-registration lookup returned HTTP 200 with one vehicle
  in 860 ms. The private response includes vehicle identity and EU-control fields.
  This is a single observed request, not a latency or availability guarantee.
- Strate Cloud Run is manually scaled to zero, Cloud SQL is STOPPED with activation
  NEVER, and its queue/scheduler are paused. Its NAT was removed and reserved
  outbound IP released. Source code, database contents, evidence and backups remain.
  Retained storage, backup and database-IP costs may continue. Vercel pause was
  confirmed by the user; independent HTTP verification returns 503 with the
  deployment-paused message.
- No native app, frontend, PostgreSQL cache, payment or booking integration exists yet.

## Next Steps

1. Complete and record the foundation/API checks in the private handoff.
2. Discuss the user's complete product vision in this repository.
3. Define vehicle response mapping and a server-only, bounded cache policy.
4. Implement the connected path with explicit cached-data fallback, then qualify
   the native journey and distribution on the intended phone.

No failed or unavailable API request may overwrite a prior successful vehicle
record. Preserve fetched-at, source and schema version; store driver mileage
separately. Test authentication errors, not-found responses and provider outages.
