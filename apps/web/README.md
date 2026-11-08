# Bilfred Website

Next.js App Router, React, Base UI and CSS Modules. Use the pinned root Node and
pnpm versions, then run from the repository root:

```sh
pnpm install --frozen-lockfile
pnpm --filter @bilfred/web dev
pnpm --filter @bilfred/web build
```

Copy `.env.example` in this directory to `.env.local` and set your own API origin
and shared waitlist secret. Both variables are server-only. The API must have the
same key and migration 0006 applied. Never use `NEXT_PUBLIC` for credentials.

The public POST route checks request origin, JSON size, email and explicit consent,
then sends a daily HMAC abuse-counter digest to FastAPI. No email is sent during
signup. PostgreSQL keeps consent text, version, time and one-year expiry; schedule
the protected cleanup endpoint daily. See the API README.

The landing page includes dated market sources and a privacy page. Keep its
controller, contact, retention and provider descriptions aligned with deployment.
Vercel builds from `apps/web`; deployment secrets belong in environment settings.
