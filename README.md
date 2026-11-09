# Bilfred

**Archived on 9 November 2026.** Development is paused after the hackathon.
The hosted website and API have been retired. Source remains available as a
reference; running the connected experience requires your own infrastructure.

A native iPhone demo for planning car maintenance in Norway. Enter a registration
number, add the mileage, review a maintenance timeline, compare three nearby
workshops, choose a time and accept a service offer. Accepted offers appear in
**Historikk**, with simulated rescheduling and completion.

The interface is SwiftUI with a full-bleed car cover, connected maintenance cards,
MapKit workshop selection, Apple Pay/Vipps example choices and swipe acceptance.
Confetti marks a saved demo order. Product copy is Norwegian Bokmål.

**This is a demonstration, not a live booking or payment service.** Workshop
prices and ratings can include demo values. Acceptance stores a demo receipt; it
does not reserve a workshop appointment, contact a provider or charge a card.

## Architecture

| Component | Implementation |
| --- | --- |
| iPhone | SwiftUI, MapKit, Core Location, protected local cache and Keychain |
| Website | Next.js App Router, React, Base UI, CSS Modules and consent-based waitlist |
| API | Python 3.12, FastAPI, PostgreSQL, explicit checksum-verified migrations |
| Research | Exa structured output, validated and cached per workshop/model |
| Vehicle facts | Statens vegvesen technical API with last-good cache fallback |
| Deployment | Cloud Run and Cloud SQL; private deployment configuration excluded |

Official EU-control dates, driver-entered mileage and proposed maintenance stay
separate. Missing service history is not evidence of missed maintenance. Research
responses retain source and retrieval metadata. Acceptance supports idempotent
retries and installation-scoped access.

## Run Locally

1. Use the Node version in `.node-version`, the pinned pnpm version in
   `package.json`, Python 3.12 and `uv`.
2. Copy `.env.example` to `.env`. Keep provider keys server-side. Configure your
   own PostgreSQL database using `DATABASE_URL`.
3. Follow [API setup](apps/api/README.md) to review/apply migrations and run the API.
4. Follow [iOS setup](apps/ios/README.md) to generate and build the Xcode project.
   The public configuration defaults to `http://localhost:8008`.
5. Follow [website setup](apps/web/README.md) for the landing page and waitlist.
   Native UI tests use isolated synthetic fixtures. Real failed lookups never invent
   a vehicle. Previously retrieved vehicle data stays available during outages.

No provider credentials are needed for the isolated UI test journey. Live lookup requires your
own Vegvesen access, and new research requires an Exa key. Workshop ingestion and
research commands are explicit operations; paid research is not run by setup.

## Verification

The API suite exercises concurrent acceptance, ownership, immutable offers,
booking changes and cache preservation. Native UI tests exercise onboarding,
keyboard dismissal, loading, workshop choice, date/time, payment selection,
partial/full swipes, history and relaunch. See each app's README for commands.

Private databases, raw research, registrations, screenshots, signing material,
build archives, deployment/account mappings and the supplied demo photo are
excluded. A public checkout uses synthetic fixtures and a car illustration.
See [third-party notices](THIRD_PARTY_NOTICES.md) and
[the Vegvesen API mapping](docs/VEGVESEN_API.md).

The former landing page at bilfred.com is offline. Bilfred Fleet was not built.
This repository is publicly
viewable; no open-source license for Bilfred's own code is granted at this time.
