"""One bounded Oslo geocoding pass against Kartverket's official address API."""

import asyncio
import json
from datetime import datetime, timezone

import httpx
import psycopg
from psycopg.rows import dict_row

from .db import ROOT, database_url

SOURCE = "https://api.kartverket.no/adresser/v1/sok"


def normalized(value: str) -> str:
    return "".join(c for c in value.lower() if c.isalnum())


async def run():
    with psycopg.connect(database_url(), row_factory=dict_row) as connection:
        rows = connection.execute("""SELECT w.approval_id,w.address,w.postcode FROM workshops w
            JOIN workshop_enrichments e USING(approval_id)
            WHERE w.county_code='03' AND w.active AND e.service='eu_kontroll'""").fetchall()
    directory = ROOT / ".local/verification/workshop-locations"
    directory.mkdir(parents=True, exist_ok=True)
    semaphore = asyncio.Semaphore(5)
    async with httpx.AsyncClient(timeout=15) as client:
        async def resolve(row):
            path = directory / f"{row['approval_id']}.json"
            if path.exists():
                return json.loads(path.read_text())
            async with semaphore:
                await asyncio.sleep(0.1)
                try:
                    response = await client.get(SOURCE, params={"sok": row["address"], "postnummer": row["postcode"], "treffPerSide": 10, "asciiKompatibel": "false"})
                    response.raise_for_status()
                    data = response.json()
                    matches = [a for a in data["adresser"] if normalized(a["adressetekst"]) == normalized(row["address"]) and a["postnummer"] == row["postcode"]]
                    points = {(a["representasjonspunkt"]["lat"], a["representasjonspunkt"]["lon"]) for a in matches}
                    result = {**row, "source": SOURCE, "retrieved_at": datetime.now(timezone.utc).isoformat(), "response": data, "point": list(points.pop()) if len(points) == 1 else None}
                except (httpx.HTTPError, ValueError, KeyError) as error:
                    result = {**row, "point": None, "error": type(error).__name__}
                path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
                return result
        results = await asyncio.gather(*(resolve(row) for row in rows))
    with psycopg.connect(database_url()) as connection:
        for result in results:
            if result["point"]:
                connection.execute("""UPDATE workshops SET latitude=%s,longitude=%s,
                    location_source=%s,location_retrieved_at=%s WHERE approval_id=%s
                    AND address=%s AND postcode=%s""",
                    (*result["point"], SOURCE, result["retrieved_at"], result["approval_id"], result["address"], result["postcode"]))
    print(json.dumps({"checked": len(results), "exact_address_matches": sum(bool(r["point"]) for r in results)}))


if __name__ == "__main__":
    asyncio.run(run())
