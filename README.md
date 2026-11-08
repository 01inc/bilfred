# Bilfred

Bilfred ordner det. A native car-maintenance concierge for the Norwegian market.

The intended first interaction is registration entry, a server-side vehicle lookup
with a PostgreSQL cache, and a clear presentation of the vehicle and its next task.
The detailed product journey is being designed. No booking, payment, workshop
partnership or maintenance diagnosis is implemented or implied.

## Foundation

- Native SwiftUI for iPhone; Norwegian Bokmål product copy.
- Next.js App Router on Vercel for the web surface.
- Python/FastAPI on Cloud Run and Cloud SQL PostgreSQL for server-side services.
- Keep API keys server-only; vehicle records and private research stay out of Git.
- Distinguish freshly retrieved data, cached data, driver input and illustrative data.
- Preserve the last successful vehicle record when the provider is unavailable.

Use the Node version in `.node-version`. Copy `.env.example` to `.env`, then set
the provider key and the private test registration locally. Run
`node scripts/check-vegvesen.mjs` to verify public reachability and, when configured,
one authenticated lookup. Responses and receipts are saved only under `.local/`.
The check does not create a database or an application cache.

See [the current plan](docs/PLAN.md). Environment mappings and continuation context
are deliberately kept in the ignored `.local/HANDOFF.md`.
