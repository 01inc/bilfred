"""Import complete verified registry snapshots and validated research receipts."""

import argparse
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import psycopg
from psycopg.types.json import Jsonb

from .db import ROOT, database_url


def clean(value: str | None) -> str:
    return " ".join((value or "").split())


def website(value: str | None) -> str | None:
    value = clean(value)
    if not value:
        return None
    if not value.startswith(("http://", "https://")):
        value = "https://" + value
    parsed = urlparse(value)
    return value if parsed.hostname and "." in parsed.hostname else None


def import_registry() -> dict:
    source = ROOT / ".local/verification/workshops/national-all.json"
    content = source.read_bytes()
    document = json.loads(content)
    oslo = json.loads((source.parent / "oslo-all.json").read_text())
    rows = document["virksomheter"]
    ids = {row["godkjenningsnr"] for row in rows}
    oslo_ids = {row["godkjenningsnr"] for row in oslo["virksomheter"]}
    if len(rows) != len(ids) or len(rows) != document["antallTreff"]:
        raise ValueError("Partial or duplicate national snapshot; current cache preserved")
    if len(oslo_ids) != oslo["antallTreff"] or not oslo_ids <= ids:
        raise ValueError("Partial Oslo snapshot; current cache preserved")
    snapshot_id = uuid.uuid4()
    values = []
    for row in rows:
        phone = re.sub(r"\D", "", row.get("telefon") or "")
        values.append((
            row["godkjenningsnr"], clean(row["organisasjonsnr"]),
            clean(row.get("organisasjonsnrHovedenhet")) or None,
            clean(row["orgNavn"]), clean(row.get("avdelingsnavn")) or None,
            clean(row["besoksAdresse"]), clean(row["besoksPostnummer"]),
            clean(row["besoksPoststed"]), website(row.get("internettAdresse")),
            ("+47" + phone if len(phone) == 8 else phone) or None,
            sorted(set(row["godkjenningsTyper"])),
            "03" if row["godkjenningsnr"] in oslo_ids else None,
            document["retrievedAt"], snapshot_id, Jsonb(row),
        ))
    with psycopg.connect(database_url()) as connection:
        connection.execute("SELECT pg_advisory_xact_lock(647283902)")
        connection.execute(
            "INSERT INTO workshop_registry_snapshots VALUES (%s,%s,%s,%s,%s,%s)",
            (snapshot_id, document["retrievedAt"], document["sourceUrl"],
             hashlib.sha256(content).hexdigest(), len(rows), len(oslo_ids)),
        )
        with connection.cursor() as cursor:
            cursor.executemany(
                """INSERT INTO workshops
                (approval_id,organization_number,parent_organization_number,name,branch_name,
                 address,postcode,city,website_url,phone,approvals,county_code,
                 source_retrieved_at,snapshot_id,raw)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (approval_id) DO UPDATE SET
                organization_number=EXCLUDED.organization_number,
                parent_organization_number=EXCLUDED.parent_organization_number,
                name=EXCLUDED.name,branch_name=EXCLUDED.branch_name,
                address=EXCLUDED.address,postcode=EXCLUDED.postcode,city=EXCLUDED.city,
                website_url=EXCLUDED.website_url,phone=EXCLUDED.phone,
                approvals=EXCLUDED.approvals,county_code=EXCLUDED.county_code,
                active=true,source_retrieved_at=EXCLUDED.source_retrieved_at,
                snapshot_id=EXCLUDED.snapshot_id,raw=EXCLUDED.raw""", values,
            )
        # Only a validated complete snapshot can deactivate absent entities.
        connection.execute(
            "UPDATE workshops SET active=false WHERE snapshot_id <> %s", (snapshot_id,)
        )
    return {"national": len(rows), "oslo": len(oslo_ids), "snapshot": str(snapshot_id)}


def import_enrichments(directory: Path) -> dict:
    if not directory.resolve().is_relative_to((ROOT / ".local").resolve()):
        raise ValueError("Research receipts must come from .local")
    imported = 0
    with psycopg.connect(database_url()) as connection:
        for path in sorted(directory.glob("*-result.json")):
            result = json.loads(path.read_text())
            record = result.get("record") or {}
            reputation = result.get("reputation") or {}
            price = record.get("price_nok") if result["status"] == "price_validated" else None
            price_source = website(record.get("source_url")) if price is not None else None
            if price is not None and (not price_source or price < 0):
                raise ValueError(f"Invalid validated price in {path.name}")
            rating_source = website(reputation.get("source_url"))
            rating = reputation.get("rating") if rating_source else None
            if rating is not None and not 0 <= rating <= 5:
                raise ValueError(f"Invalid rating in {path.name}")
            now = datetime.now(timezone.utc)
            retrieved = record.get("retrieved_at") or reputation.get("retrieved_at") or now
            raw = {"result": result}
            for suffix in ("discovery", "contents"):
                evidence = directory / f"{result['approvalId']}-{suffix}.json"
                if evidence.exists():
                    raw[suffix] = json.loads(evidence.read_text())
            with connection.transaction():
                connection.execute(
                    """INSERT INTO workshop_enrichment_runs VALUES (%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (run_key) DO NOTHING""",
                    (f"{directory.name}/{result['approvalId']}", result["approvalId"],
                     "eu_kontroll", retrieved, result["status"], Jsonb(raw)),
                )
                connection.execute(
                    """INSERT INTO workshop_enrichments
                    (approval_id,service,price_nok,price_type,price_source_url,price_source_kind,
                     price_retrieved_at,rating,review_count,rating_source_url,rating_retrieved_at,
                     public_customers,last_attempt_at,last_attempt_status)
                    VALUES (%s,'eu_kontroll',%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (approval_id,service) DO UPDATE SET
                    price_nok=COALESCE(EXCLUDED.price_nok,workshop_enrichments.price_nok),
                    price_type=CASE WHEN EXCLUDED.price_nok IS NOT NULL THEN EXCLUDED.price_type ELSE workshop_enrichments.price_type END,
                    price_source_url=CASE WHEN EXCLUDED.price_nok IS NOT NULL THEN EXCLUDED.price_source_url ELSE workshop_enrichments.price_source_url END,
                    price_source_kind=CASE WHEN EXCLUDED.price_nok IS NOT NULL THEN EXCLUDED.price_source_kind ELSE workshop_enrichments.price_source_kind END,
                    price_retrieved_at=CASE WHEN EXCLUDED.price_nok IS NOT NULL THEN EXCLUDED.price_retrieved_at ELSE workshop_enrichments.price_retrieved_at END,
                    rating=COALESCE(EXCLUDED.rating,workshop_enrichments.rating),
                    review_count=CASE WHEN EXCLUDED.rating IS NOT NULL THEN EXCLUDED.review_count ELSE workshop_enrichments.review_count END,
                    rating_source_url=CASE WHEN EXCLUDED.rating IS NOT NULL THEN EXCLUDED.rating_source_url ELSE workshop_enrichments.rating_source_url END,
                    rating_retrieved_at=CASE WHEN EXCLUDED.rating IS NOT NULL THEN EXCLUDED.rating_retrieved_at ELSE workshop_enrichments.rating_retrieved_at END,
                    public_customers=COALESCE(EXCLUDED.public_customers,workshop_enrichments.public_customers),
                    last_attempt_at=EXCLUDED.last_attempt_at,last_attempt_status=EXCLUDED.last_attempt_status
                    WHERE EXCLUDED.last_attempt_at >= workshop_enrichments.last_attempt_at""",
                    (result["approvalId"], price, record.get("price_type") if price is not None else None,
                     price_source, result.get("sourceKind") if price is not None else None,
                     record.get("retrieved_at") if price is not None else None,
                     rating, reputation.get("review_count") if rating is not None else None,
                     rating_source if rating is not None else None,
                     reputation.get("retrieved_at") if rating is not None else None,
                     result.get("publicCustomers"), retrieved, result["status"]),
                )
            imported += 1
    return {"importedEnrichments": imported}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["registry", "enrichments", "stats"])
    parser.add_argument("directory", nargs="?")
    args = parser.parse_args()
    if args.action == "registry":
        print(json.dumps(import_registry()))
    elif args.action == "enrichments":
        print(json.dumps(import_enrichments(Path(args.directory))))
    else:
        with psycopg.connect(database_url()) as connection:
            row = connection.execute("""SELECT
              (SELECT count(*) FROM workshops WHERE active),
              (SELECT count(*) FROM workshops WHERE active AND county_code='03'),
              count(*),count(price_nok),count(rating),
              count(*) FILTER (WHERE price_nok IS NOT NULL AND rating IS NOT NULL)
              FROM workshop_enrichments""").fetchone()
            print(json.dumps(dict(zip(
                ["national", "oslo", "enriched", "withPrice", "withRating", "withBoth"], row
            ))))


if __name__ == "__main__":
    main()
