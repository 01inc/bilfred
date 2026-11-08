# Bilfred Engineering Contract

Read README.md, docs/PLAN.md and the ignored .local/HANDOFF.md before working.
Keep verified state current. Discuss the user's product vision before implementing
the customer flow; foundation setup does not authorize invented product decisions.

Bilfred is a separate project. Preserve Strate and do not copy its application
code, reference assets, evidence, customer data or credentials. Use synthetic
fixtures in source. Private handoffs, registrations, provider responses, account
mappings, logs and deployment receipts belong in ignored .local/ or credential
storage. API keys are server-only, never iOS constants or NEXT_PUBLIC variables.

Use native SwiftUI for iOS; Next.js App Router, React, Base UI and CSS Modules for
web; Python/FastAPI on Cloud Run and Cloud SQL PostgreSQL for server services.
Use pnpm with pinned Node, and uv with a lockfile for any Python project.
Review migration SQL explicitly; no schema push. Consult current official and
installed framework documentation before API changes.

Every cloud command must explicitly select Bilfred's configuration, project and
account from private deployment configuration. Never change global CLI defaults
or use Strate resources for Bilfred. Bound costs before provisioning paid capacity.

Speak English with the user. Product copy is Norwegian Bokmål. Distinguish vehicle
facts, driver-entered mileage, suggestions, offers, acceptance and confirmed
appointments. Cache outage fallback must retain source and original retrieval time;
failed lookups must not erase valid records or invent a vehicle. Only call an actual
appointment confirmed when the fulfillment system has confirmed it.

Prefer CLI build/test/distribution, then TestFlight on the phone. Do not resume
cable troubleshooting. Keep the core demonstration recoverable during provider
outages. Never claim unavailable tests or live integrations passed.

Git identity: Alf Viktor Williamsen <mail@alfviktor.com>.
