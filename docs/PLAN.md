# Bilfred Build Plan

## Archived

Development was paused on 9 November 2026 after the hackathon. The hosted website
and API were retired, and private database backups, builds and recovery notes are
preserved locally. The sections below describe the final implementation, not an
active delivery plan. Do not provision services or restart research automatically.

## Implemented Journey

Native registration input → vehicle reveal → entered mileage → car cover and
connected maintenance timeline → three workshop options on a map → requested
date/time → offer and example payment choice → swipe acceptance → demo history.

The interface uses adaptive neutral surfaces, system typography and blue accents.
Onboarding centers the content above bottom actions. Text inputs have a keyboard
close control. Blocking loads show a centered spinner. A short confetti burst
marks acceptance, with Reduce Motion respected.

## Data And Services

The FastAPI backend supports vehicle lookup/cache, driver mileage, maintenance
research/cache, three ranked options, versioned offers, idempotent acceptance and
mutable demo booking requests. PostgreSQL has six explicit migrations; runtime
startup never applies DDL. Workshop records and Exa enrichment are cached per
entity. Location is approximated to an area before server research.

The official EU deadline comes from Statens vegvesen. Researched maintenance
intervals and proposed future dates remain separate. Drivers can record completed
work, because mileage alone cannot establish service history.

## Demonstration Boundaries

- Exactly three options with price and reputation; demo values can fill gaps.
- Apple Pay and Vipps are example selections, without payment SDKs or charges.
- Acceptance saves a demo receipt, without reserving or confirming a workshop time.
- History supports simulated rescheduling and completion.
- Failed live lookups preserve valid cached facts and their original retrieval time.
- Public source contains synthetic fixtures; private responses, deployment mappings,
  signing material and supplied photography remain outside Git.

## Qualification And Next Work

The backend suite covers ownership, concurrent retries, offer immutability,
booking changes and cache preservation. Native UI tests cover keyboard/loading
states and the complete option/time/payment/swipe/history/relaunch sequence.
TestFlight is the device distribution path. Test evidence and deployment receipts
are kept privately rather than embedded as customer data in the repository.

Actual workshop availability, contracted offers, fulfillment and payment remain
future integration work. Bilfred Fleet remains future scope.

## Landing Page And Waitlist

A responsive Next.js landing page uses the keynote gradient and market figures
with dated sources. The waitlist requires explicit consent and validates email on
both the web server and FastAPI. A server-only key protects the API; PostgreSQL
stores consent text, version, timestamp and expiry. Daily cleanup removes expired
signups and short-lived abuse counters. No tracking or automatic outreach is used.
