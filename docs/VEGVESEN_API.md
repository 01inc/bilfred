# Vegvesen API Mapping

Verified 8 November 2026. Scope: EU-kontroll dates and mileage through the
technical vehicle lookup API. No application integration is implemented yet.

## Lookup

`GET https://akfell-datautlevering.atlas.vegvesen.no/enkeltoppslag/kjoretoydata`

- Send exactly one query parameter: `kjennemerke` (registration number) or
  `understellsnummer` (VIN).
- Authenticate server-side with `SVV-Authorization: Apikey <key>`.
- Request JSON with `Accept: application/json`.
- Vehicle records are returned in `kjoretoydataListe`.
- Normalize registration whitespace and case when comparing identities.

The [official portal](https://autosys-kjoretoy-api.atlas.vegvesen.no/api-ui/index-api.html?apiId=enkeltoppslag)
documents the lookup. The [data catalogue](https://dataut.vegvesen.no/dataservice/kjoretoyopplysninger-tekniske-data-enkeltoppslag)
also lists this gateway, which was tested with the same results:

`https://www.vegvesen.no/ws/no/vegvesen/kjoretoy/felles/datautlevering/enkeltoppslag/kjoretoydata`

## Field Mapping

Paths are relative to one vehicle in `kjoretoydataListe`.

| Data | Field | Availability |
| --- | --- | --- |
| EU-kontroll deadline | `periodiskKjoretoyKontroll.kontrollfrist` | Date; verified in live responses |
| Last approved EU-kontroll | `periodiskKjoretoyKontroll.sistGodkjent` | Date; verified in live responses; not necessarily the latest inspection attempt |
| Mileage at used import | `godkjenning.forstegangsGodkjenning.bruktimport.kilometerstand` | Optional integer in the schema; absent in the tested vehicle; actual availability through our access remains unverified |
| Current mileage | No documented field | Obtain separately from the driver |
| EU-kontroll mileage history | No documented field in this API | Vegvesen directs users to logged-in Din side |

The [current OpenAPI schema](https://akfell-datautlevering.atlas.vegvesen.no/v3/api-docs)
includes the optional import-mileage field. The
[official distribution schema](https://akfell-oppslag.atlas.vegvesen.no/v3/api-docs/A.%20Kjoretoydistribusjon%20v2)
describes it as mileage at import. Its presence in a schema does not establish
that our subscription receives it. Never interpret it as current mileage or an
EU-kontroll reading.

[Vegvesen's mileage explanation](https://www.vegvesen.no/kjoretoy/kjop-og-salg/kjoretoyopplysninger/sjekk-kjoretoyopplysninger/om-tjenesten)
describes historical inspection readings on Din side. That service is separate
from this API and was not tested while logged in.

## Verification

Eight live requests used one privately configured vehicle. Both URLs were tested.

| Input | Direct API | Published gateway |
| --- | --- | --- |
| Registration only | 200 | 200 |
| VIN only | 200 | 200 |
| Both identifiers | 400 | 400 |
| Neither identifier | 400 | 400 |

All four successful responses were identical, identified the expected vehicle,
contained both EU dates and contained no mileage field. The used-import object
was absent. These observations do not establish availability for other vehicles.

The review covered the 92-schema OpenAPI document, all 13 listed portal API
descriptions, and public schemas for restricted vehicle distribution, history
and additional information. Restricted data access, personal plates, quota
exhaustion and provider outages were not live-tested in this verification.

Private responses, receipts and the detailed report remain under
`.local/verification/vegvesen-mapping/` and must stay out of Git.

## Integration Rules

- Missing dates or mileage remain unknown; never substitute zero or invented data.
- Preserve provider source and original retrieval time when serving cached dates.
  A failed refresh must not erase the last successful record.
- Store driver-entered mileage separately, with its reading date and source.
- Keep API keys server-only and real registrations, VINs and responses out of source.
- Handle response codes explicitly: the OpenAPI documents 204 (no vehicle),
  400 (invalid input) and 422 (quota); the portal also documents 403 and 429.
  An earlier unauthenticated probe returned 401. Only the 200/400 cases above
  were exercised by this targeted verification.
