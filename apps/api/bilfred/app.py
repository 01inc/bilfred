import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from typing import Annotated

import psycopg
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from .db import database_url
from .models import AcceptInput, BookingUpdate, HistoryInput, MileageInput, OfferInput, ServiceSearch, VehicleLookup
from .maintenance import cached_guidance, proposed_events
from .options import service_options
from .vehicle import get_vehicle_facts
from . import research_jobs
from .waitlist import router as waitlist_router

app = FastAPI(title="Bilfred", version="0.1.0")
app.include_router(waitlist_router)


def vehicle_image(facts: dict) -> str | None:
    return "/assets/superb.webp" if facts["make"] == "Škoda" and facts["model"] == "Superb" else None


def connect():
    return psycopg.connect(database_url(), row_factory=dict_row)


def session(authorization: Annotated[str | None, Header()] = None) -> uuid.UUID:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Åpne appen på nytt for å fortsette.")
    token_hash = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with connect() as connection:
        row = connection.execute("SELECT id FROM installations WHERE token_hash=%s", (token_hash,)).fetchone()
    if not row:
        raise HTTPException(401, "Økten er utløpt. Åpne appen på nytt.")
    return row["id"]


Session = Annotated[uuid.UUID, Depends(session)]


def owned_vehicle(vehicle_id: uuid.UUID, installation_id: uuid.UUID) -> dict:
    with connect() as connection:
        row = connection.execute("""SELECT v.*,c.facts,c.source_retrieved_at FROM vehicles v
            JOIN vehicle_cache c USING (lookup_key) WHERE v.id=%s AND v.installation_id=%s""",
            (vehicle_id, installation_id)).fetchone()
    if not row:
        raise HTTPException(404, "Bilen finnes ikke i denne økten.")
    return row


@app.get("/health")
def health():
    with connect() as connection:
        connection.execute("SELECT 1")
    return {"status": "ok", "version": "0.1.0"}


@app.get("/assets/superb.webp")
def hero():
    path = Path(__file__).parent / "assets/superb.webp"
    if not path.exists():
        raise HTTPException(404, "Image unavailable")
    return FileResponse(path, media_type="image/webp", headers={"Cache-Control": "public, max-age=86400"})


@app.post("/v1/installations", status_code=201)
def create_installation():
    identifier = uuid.uuid4()
    token = secrets.token_urlsafe(48)
    with connect() as connection:
        connection.execute("INSERT INTO installations (id,token_hash) VALUES (%s,%s)",
                           (identifier, hashlib.sha256(token.encode()).hexdigest()))
    return {"id": str(identifier), "token": token}


@app.post("/v1/vehicles/lookup")
def vehicle_lookup(body: VehicleLookup, installation_id: Session):
    key, facts = get_vehicle_facts(body.registration, body.demo)
    with connect() as connection:
        row = connection.execute("""INSERT INTO vehicles (id,installation_id,lookup_key,demo)
            VALUES (%s,%s,%s,%s) ON CONFLICT (installation_id,lookup_key) DO UPDATE
            SET lookup_key=EXCLUDED.lookup_key RETURNING id""",
            (uuid.uuid4(), installation_id, key, body.demo)).fetchone()
    return {"vehicle_id": str(row["id"]), "facts": facts, "image_url": vehicle_image(facts)}


@app.post("/v1/vehicles/{vehicle_id}/mileage", status_code=201)
def mileage(vehicle_id: uuid.UUID, body: MileageInput, installation_id: Session):
    owned_vehicle(vehicle_id, installation_id)
    if body.observed_on > datetime.now(timezone.utc).date():
        raise HTTPException(422, "Datoen kan ikke være i fremtiden.")
    identifier = uuid.uuid4()
    with connect() as connection:
        connection.execute("""INSERT INTO mileage_readings (id,vehicle_id,km,observed_on)
            VALUES (%s,%s,%s,%s)""", (identifier, vehicle_id, body.km, body.observed_on))
    return {"id": str(identifier), "km": body.km, "observed_on": body.observed_on, "source": "driver"}


@app.post("/v1/vehicles/{vehicle_id}/history", status_code=201)
def history(vehicle_id: uuid.UUID, body: HistoryInput, installation_id: Session):
    owned_vehicle(vehicle_id, installation_id)
    if body.completed_on and body.completed_on > datetime.now(timezone.utc).date():
        raise HTTPException(422, "Datoen kan ikke være i fremtiden.")
    identifier = uuid.uuid4()
    with connect() as connection:
        connection.execute("""INSERT INTO service_history (id,vehicle_id,service,completed_on,km)
            VALUES (%s,%s,%s,%s,%s)""", (identifier, vehicle_id, body.service, body.completed_on, body.km))
    return {"id": str(identifier), "source": "driver"}


@app.get("/v1/vehicles/{vehicle_id}/home")
def home(vehicle_id: uuid.UUID, installation_id: Session):
    vehicle = owned_vehicle(vehicle_id, installation_id)
    with connect() as connection:
        research = cached_guidance(connection, vehicle["facts"])
        reading = connection.execute("""SELECT km,observed_on FROM mileage_readings
            WHERE vehicle_id=%s ORDER BY recorded_at DESC LIMIT 1""", (vehicle_id,)).fetchone()
        completed = connection.execute("""SELECT service,completed_on,km FROM service_history
            WHERE vehicle_id=%s ORDER BY recorded_at DESC""", (vehicle_id,)).fetchall()
        accepted = connection.execute("""SELECT a.receipt FROM acceptances a JOIN offers o
            ON o.id=a.offer_id WHERE o.vehicle_id=%s AND a.installation_id=%s
            ORDER BY a.accepted_at DESC LIMIT 1""", (vehicle_id, installation_id)).fetchone()
    facts = {**vehicle["facts"], "fetched_at": vehicle["source_retrieved_at"].isoformat(),
             "cache_state": "demo" if vehicle["demo"] else ("stale_cache" if vehicle["source_retrieved_at"] < datetime.now(timezone.utc)-timedelta(hours=24) else "fresh_cache")}
    done_services = {r["service"] for r in completed}
    timeline = [
        {"id": "eu_kontroll", "title": "EU-kontroll", "subtitle": "Periodisk kontroll av bilen.",
         "kind": "demo" if vehicle["demo"] else "official", "due_on": facts.get("eu_due_on"),
         "why": "Fristen kommer fra Statens vegvesen." if not vehicle["demo"] else "Eksempel på en kontrollfrist.",
         "state": "recorded" if "eu_kontroll" in done_services else "upcoming"},
        {"id": "service", "title": "Neste service", "subtitle": "Servicehistorikk mangler.",
         "kind": "suggestion", "due_on": None,
         "why": "Vi trenger tidligere servicehistorikk før vi kan fastslå neste serviceintervall.",
         "state": "recorded" if "service" in done_services else "suggested"},
        {"id": "tires", "title": "Dekksjekk", "subtitle": "Dekk, mønsterdybde og lufttrykk.",
         "kind": "suggestion", "due_on": None, "why": "En sesongkontroll er et forslag, ikke en diagnose.",
         "state": "recorded" if "tires" in done_services else "suggested"},
    ]
    if research and research.get("schema_version") == 2:
        timeline = [timeline[0], *proposed_events(research, done_services)]
        timeline.sort(key=lambda event: (event["due_on"] or "9999-12-31", event["id"]))
    elif research:
        timeline[1].update({
            "subtitle": "Produsentens veiledning, tilpasset bilens drivlinje.",
            "why": "Vi har funnet serviceveiledning for denne biltypen. Modellvariant og tidligere service må bekreftes før vi setter neste frist.",
            "guidance": [g for g in research["guidance"] if g["service"] == "service"],
            "research_retrieved_at": research["retrieved_at"],
        })
        brake_guidance = [g for g in research["guidance"] if g["service"] == "brakes"]
        if brake_guidance:
            timeline[2].update({"id": "brakes", "title": "Bremsekontroll",
                                "subtitle": "Særlig relevant for en ladbar hybrid.",
                                "why": "Produsenten anbefaler kontroll av bremsene ved service. Behovet avhenger av bruk, ikke en fast utskiftingsfrist.",
                                "guidance": brake_guidance,
                                "state": "recorded" if "brakes" in done_services else "suggested"})
    return {"vehicle_id": str(vehicle_id), "facts": facts, "mileage": reading,
            "image_url": vehicle_image(facts), "timeline": timeline,
            "history": completed, "maintenance_research": research,
            "acceptance": accepted["receipt"] if accepted else None}


@app.post("/v1/service-searches")
def search(body: ServiceSearch, installation_id: Session):
    owned_vehicle(body.vehicle_id, installation_id)
    return {"mode": "demo", "area": body.area.model_dump(), "coverage_area": "Oslo",
            "notice": "Demotilbud · Ingen faktisk bestilling", "options": service_options(body.area.model_dump(), body.service)}


@app.post("/v1/vehicles/{vehicle_id}/research")
def start_research(vehicle_id: uuid.UUID, installation_id: Session):
    vehicle = owned_vehicle(vehicle_id, installation_id)
    if vehicle["demo"]:
        return {"status": "demo", "cache_hit": True}
    return research_jobs.start(connect, vehicle["facts"])


@app.get("/v1/vehicles/{vehicle_id}/research")
def research_status(vehicle_id: uuid.UUID, installation_id: Session):
    vehicle = owned_vehicle(vehicle_id, installation_id)
    if vehicle["demo"]:
        return {"status": "demo", "cache_hit": True}
    return research_jobs.status(connect, vehicle["facts"])


@app.post("/v1/offers", status_code=201)
def offer(body: OfferInput, installation_id: Session):
    vehicle = owned_vehicle(body.vehicle_id, installation_id)
    options = service_options(body.area.model_dump(), body.service)
    option = next((o for o in options if o["id"] == body.option_id), None)
    if option is None:
        raise HTTPException(409, "Alternativet er endret. Hent tilbudene på nytt.")
    identifier = uuid.uuid4()
    now = datetime.now(timezone.utc)
    expires = now + timedelta(hours=24)
    proposed_day = now.date() + timedelta(days=7)
    with connect() as connection:
        research = cached_guidance(connection, vehicle["facts"])
    if body.service == "eu_kontroll" and vehicle["facts"].get("eu_due_on"):
        proposed_day = max(proposed_day, datetime.fromisoformat(vehicle["facts"]["eu_due_on"]).date() - timedelta(days=14))
    elif research and research.get("schema_version") == 2:
        event = next((e for e in proposed_events(research, set()) if e["id"] == body.service), None)
        if event:
            proposed_day = max(proposed_day, datetime.fromisoformat(event["due_on"]).date())
    months = ["januar", "februar", "mars", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "desember"]
    desired = body.appointment_at or datetime.combine(proposed_day, datetime.min.time().replace(hour=10), tzinfo=ZoneInfo("Europe/Oslo"))
    if desired <= now or desired > now + timedelta(days=1096):
        raise HTTPException(422, "Velg et fremtidig tidspunkt innen tre år.")
    local_time = desired.astimezone(ZoneInfo("Europe/Oslo"))
    titles = {"eu_kontroll": "EU-kontroll", "service": "Servicegjennomgang", "tires": "Dekksjekk",
              "brakes": "Bremsekontroll", "oil_service": "Oljeservice", "inspection": "Inspeksjonsservice",
              "brake_fluid": "Bremsevæske", "cabin_filter": "Kupéfilter", "gearbox_service": "Girkasseservice",
              "timing_belt": "Registerreimkontroll", "battery_check": "Batterisjekk",
              "spark_plugs": "Tennplugger", "air_filter": "Luftfilter"}
    snapshot = {"id": str(identifier), "version": 1, "mode": "demo", "service": body.service,
                "title": titles[body.service], "workshop": option, "price_ore": option["price_ore"],
                "currency": "NOK", "appointment_label": f"{local_time.day}. {months[local_time.month-1]} {local_time.year} · kl. {local_time:%H.%M}",
                "appointment_at": desired.isoformat(),
                "appointment_source": "demo", "includes": [titles[body.service], "Rapport fra verkstedet", "Tilleggsarbeid avtales separat"],
                "terms": "Demonstrasjon. Ingen betaling eller faktisk verkstedtime opprettes.",
                "expires_at": expires.isoformat()}
    with connect() as connection:
        connection.execute("""INSERT INTO offers
            (id,installation_id,vehicle_id,mode,snapshot,expires_at) VALUES (%s,%s,%s,'demo',%s,%s)""",
            (identifier, installation_id, body.vehicle_id, Jsonb(snapshot), expires))
    return snapshot


@app.post("/v1/offers/{offer_id}/acceptances")
def accept(offer_id: uuid.UUID, body: AcceptInput, installation_id: Session):
    with connect() as connection:
        # Serialize this installation's attempts so parallel retries cannot create
        # multiple receipts or reuse the same key against different offers.
        connection.execute("SELECT id FROM installations WHERE id=%s FOR UPDATE", (installation_id,))
        prior = connection.execute("""SELECT * FROM acceptances
            WHERE installation_id=%s AND idempotency_key=%s""", (installation_id, str(body.idempotency_key))).fetchone()
        if prior:
            if prior["offer_id"] != offer_id or prior["offer_version"] != body.offer_version or prior["receipt"]["offer"].get("payment_method", "apple_pay") != body.payment_method:
                raise HTTPException(409, "Dette forsøket gjelder et annet tilbud.")
            return prior["receipt"]
        row = connection.execute("SELECT * FROM offers WHERE id=%s AND installation_id=%s FOR UPDATE",
                                 (offer_id, installation_id)).fetchone()
        if not row:
            raise HTTPException(404, "Tilbudet finnes ikke.")
        if row["version"] != body.offer_version:
            raise HTTPException(409, "Tilbudet er endret. Se de nye detaljene.")
        existing = connection.execute("SELECT receipt FROM acceptances WHERE offer_id=%s", (offer_id,)).fetchone()
        if existing:
            return existing["receipt"]
        if row["expires_at"] < datetime.now(timezone.utc):
            raise HTTPException(409, "Tilbudet er utløpt. Hent et nytt tilbud.")
        identifier = uuid.uuid4()
        selected_offer = {**row["snapshot"], "payment_method": body.payment_method}
        receipt = {"id": str(identifier), "offer_id": str(offer_id), "status": "demo_accepted",
                   "accepted_at": datetime.now(timezone.utc).isoformat(), "offer": selected_offer,
                   "message": "Demobestilling lagret", "detail": "Ingen betaling er trukket, og ingen faktisk verkstedtime er opprettet."}
        connection.execute("""INSERT INTO acceptances
            (id,installation_id,offer_id,offer_version,idempotency_key,status,receipt)
            VALUES (%s,%s,%s,%s,%s,'demo_accepted',%s)""",
            (identifier, installation_id, offer_id, body.offer_version, str(body.idempotency_key), Jsonb(receipt)))
        connection.execute("""INSERT INTO demo_bookings(id,installation_id,appointment_at,payment_method)
            VALUES (%s,%s,%s,%s)""", (identifier, installation_id, selected_offer.get("appointment_at"), body.payment_method))
    return receipt


@app.get("/v1/acceptances/{acceptance_id}")
def receipt(acceptance_id: uuid.UUID, installation_id: Session):
    with connect() as connection:
        row = connection.execute("SELECT receipt FROM acceptances WHERE id=%s AND installation_id=%s",
                                 (acceptance_id, installation_id)).fetchone()
    if not row:
        raise HTTPException(404, "Bestillingen finnes ikke.")
    return row["receipt"]


@app.get("/v1/bookings")
def bookings(installation_id: Session):
    with connect() as connection:
        rows = connection.execute("""SELECT b.*,a.receipt FROM demo_bookings b
            JOIN acceptances a ON a.id=b.id WHERE b.installation_id=%s
            ORDER BY b.updated_at DESC""", (installation_id,)).fetchall()
    return {"bookings": [{"id": str(r["id"]), "state": r["state"], "revision": r["revision"],
                          "appointment_at": r["appointment_at"], "payment_method": r["payment_method"],
                          "receipt": r["receipt"], "mode": "demo"} for r in rows]}


@app.patch("/v1/bookings/{booking_id}")
def update_booking(booking_id: uuid.UUID, body: BookingUpdate, installation_id: Session):
    if body.appointment_at and not datetime.now(timezone.utc) < body.appointment_at < datetime.now(timezone.utc) + timedelta(days=1096):
        raise HTTPException(422, "Velg et fremtidig tidspunkt innen tre år.")
    with connect() as connection:
        row = connection.execute("SELECT * FROM demo_bookings WHERE id=%s AND installation_id=%s FOR UPDATE",
                                 (booking_id, installation_id)).fetchone()
        if not row:
            raise HTTPException(404, "Bestillingen finnes ikke.")
        if row["revision"] != body.revision:
            raise HTTPException(409, "Bestillingen er endret. Oppdater historikken og prøv igjen.")
        if row["state"] == "completed" and body.appointment_at:
            raise HTTPException(409, "En fullført demobestilling kan ikke flyttes.")
        connection.execute("""UPDATE demo_bookings SET appointment_at=COALESCE(%s,appointment_at),
            state=COALESCE(%s,state),revision=revision+1,updated_at=now() WHERE id=%s""",
            (body.appointment_at, body.state, booking_id))
    return {"id": str(booking_id), "revision": body.revision+1, "mode": "demo"}
