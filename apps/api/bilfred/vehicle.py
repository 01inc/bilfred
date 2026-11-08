import hashlib
import os
import re
from datetime import datetime, timedelta, timezone

import httpx
import psycopg
from fastapi import HTTPException
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .db import database_url


def normalize_registration(value: str) -> str:
    value = re.sub(r"\s+", "", value).upper()
    if not value or len(value) > 12 or not all(c.isalnum() for c in value):
        raise HTTPException(422, "Kontroller registreringsnummeret.")
    return value


def lookup_key(registration: str) -> str:
    return hashlib.sha256(registration.encode()).hexdigest()


def map_vehicle(body: dict, registration: str) -> dict:
    rows = body.get("kjoretoydataListe") or []
    if len(rows) != 1:
        raise ValueError("Expected exactly one vehicle")
    row = rows[0]
    plates = [x.get("kjennemerke", "") for x in row.get("kjennemerke", [])]
    if registration not in [re.sub(r"\s+", "", x).upper() for x in plates]:
        raise ValueError("Upstream vehicle identity mismatch")
    technical = row.get("godkjenning", {}).get("tekniskGodkjenning", {}).get("tekniskeData", {})
    general = technical.get("generelt", {})
    make = next((x.get("merke") for x in general.get("merke", []) if x.get("merke")), None)
    model = next(iter(general.get("handelsbetegnelse", [])), None)
    if not make or not model:
        raise ValueError("Vehicle identity missing")
    eu = row.get("periodiskKjoretoyKontroll") or {}
    drivetrain = technical.get("motorOgDrivverk") or {}
    return {
        "registration": registration,
        "make": "Škoda" if make.upper() == "SKODA" else make.title(),
        "model": model.title(),
        "first_registered_on": row.get("forstegangsregistrering", {}).get("registrertForstegangNorgeDato"),
        "eu_due_on": eu.get("kontrollfrist"),
        "eu_last_approved_on": eu.get("sistGodkjent"),
        "vehicle_class": general.get("tekniskKode", {}).get("kodeVerdi"),
        "type_designation": general.get("typebetegnelse"),
        "powertrain": (drivetrain.get("hybridKategori") or {}).get("kodeBeskrivelse"),
        "research_context": {"drivetrain": drivetrain},
        "source": "Statens vegvesen",
        "demo": False,
    }


def get_vehicle_facts(registration: str, demo: bool = False) -> tuple[str, dict]:
    if demo:
        key = "demo:superb:v1"
        facts = {"registration": "DEMO", "make": "Škoda", "model": "Superb",
                 "first_registered_on": "2020-06-15", "eu_due_on": "2026-11-30",
                 "eu_last_approved_on": "2024-11-12", "vehicle_class": "M1",
                 "type_designation": None, "source": "Demodata", "demo": True}
        now = datetime.now(timezone.utc)
        with psycopg.connect(database_url()) as connection:
            connection.execute("""INSERT INTO vehicle_cache (lookup_key,facts,source_retrieved_at)
                VALUES (%s,%s,%s) ON CONFLICT (lookup_key) DO NOTHING""", (key, Jsonb(facts), now))
        return key, {**facts, "fetched_at": now.isoformat(), "cache_state": "demo"}
    registration = normalize_registration(registration)
    key = lookup_key(registration)
    with psycopg.connect(database_url(), row_factory=dict_row) as connection:
        cached = connection.execute("SELECT * FROM vehicle_cache WHERE lookup_key=%s", (key,)).fetchone()
    now = datetime.now(timezone.utc)
    if cached and cached["source_retrieved_at"] > now - timedelta(hours=24):
        return key, {**cached["facts"], "fetched_at": cached["source_retrieved_at"].isoformat(), "cache_state": "fresh_cache"}
    error = None
    try:
        api_key = os.environ.get("VEGVESEN_API_KEY")
        if not api_key:
            raise RuntimeError("Vehicle provider not configured")
        response = httpx.get(
            "https://akfell-datautlevering.atlas.vegvesen.no/enkeltoppslag/kjoretoydata",
            params={"kjennemerke": registration},
            headers={"SVV-Authorization": f"Apikey {api_key}", "Accept": "application/json"},
            timeout=12, follow_redirects=False,
        )
        if response.status_code == 204:
            error = HTTPException(404, "Vi fant ikke bilen. Kontroller nummeret.")
        elif response.status_code == 400:
            error = HTTPException(422, "Kontroller registreringsnummeret.")
        elif response.status_code in (401, 403, 422, 429):
            error = HTTPException(503, "Kjøretøyoppslag er midlertidig utilgjengelig.")
        else:
            response.raise_for_status()
            facts = map_vehicle(response.json(), registration)
            with psycopg.connect(database_url()) as connection:
                connection.execute("""INSERT INTO vehicle_cache (lookup_key,facts,source_retrieved_at)
                    VALUES (%s,%s,%s) ON CONFLICT (lookup_key) DO UPDATE SET
                    facts=EXCLUDED.facts,source_retrieved_at=EXCLUDED.source_retrieved_at,
                    last_attempt_at=now()""", (key, Jsonb(facts), now))
            return key, {**facts, "fetched_at": now.isoformat(), "cache_state": "live"}
    except (httpx.HTTPError, ValueError, RuntimeError):
        error = HTTPException(503, "Vi får ikke kontakt med Statens vegvesen akkurat nå.")
    if cached and error.status_code == 503:
        return key, {**cached["facts"], "fetched_at": cached["source_retrieved_at"].isoformat(), "cache_state": "stale_cache"}
    raise error
