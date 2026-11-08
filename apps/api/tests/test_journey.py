"""Integration checks against an isolated, disposable PostgreSQL schema."""

import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import httpx
import psycopg
from psycopg.types.json import Jsonb

from bilfred import vehicle
from bilfred.db import database_url



def installation(client):
    response = client.post("/v1/installations")
    assert response.status_code == 201
    return {"Authorization": "Bearer " + response.json()["token"]}


def journey(client):
    headers = installation(client)
    result = client.post("/v1/vehicles/lookup", headers=headers,
                         json={"registration": "DEMO", "demo": True})
    assert result.status_code == 200
    vehicle_id = result.json()["vehicle_id"]
    area = {"name": "Oslo", "latitude": 59.9139, "longitude": 10.7522}
    body = {"vehicle_id": vehicle_id, "area": area, "service": "eu_kontroll"}
    options = client.post("/v1/service-searches", headers=headers, json=body).json()["options"]
    assert len(options) == 3
    assert all(o["price_ore"] > 0 and 0 <= o["rating"] <= 5 for o in options)
    offer = client.post("/v1/offers", headers=headers,
                        json={**body, "option_id": options[1]["id"]})
    assert offer.status_code == 201
    assert offer.json()["workshop"]["id"] == options[1]["id"]
    return headers, vehicle_id, offer.json(), body


def test_journey_concurrent_acceptance_and_ownership(client):
    headers, vehicle_id, offer, _ = journey(client)
    response = client.post(f"/v1/vehicles/{vehicle_id}/mileage", headers=headers,
                           json={"km": 124239, "observed_on": "2026-11-08"})
    assert response.status_code == 201
    key = str(uuid.uuid4())
    payload = {"offer_version": offer["version"], "idempotency_key": key}
    def submit(_):
        response = client.post(f"/v1/offers/{offer['id']}/acceptances", headers=headers, json=payload)
        assert response.status_code == 200
        return response.json()
    with ThreadPoolExecutor(max_workers=6) as executor:
        receipts = list(executor.map(submit, range(6)))
    assert len({r["id"] for r in receipts}) == 1
    assert receipts[0]["status"] == "demo_accepted"
    assert client.get(f"/v1/vehicles/{vehicle_id}/home", headers=headers).json()["acceptance"] == receipts[0]
    outsider = installation(client)
    assert client.get(f"/v1/vehicles/{vehicle_id}/home", headers=outsider).status_code == 404
    assert client.get(f"/v1/acceptances/{receipts[0]['id']}", headers=outsider).status_code == 404
    assert client.post(f"/v1/offers/{offer['id']}/acceptances", headers=outsider, json=payload).status_code == 404


def test_acceptance_rejects_expiry_version_and_key_reuse(client):
    headers, _, offer, body = journey(client)
    key = str(uuid.uuid4())
    endpoint = f"/v1/offers/{offer['id']}/acceptances"
    assert client.post(endpoint, headers=headers, json={"offer_version": 2, "idempotency_key": key}).status_code == 409
    payload = {"offer_version": 1, "idempotency_key": key}
    assert client.post(endpoint, headers=headers, json=payload).status_code == 200
    second = client.post("/v1/offers", headers=headers, json={**body, "option_id": "demo-1"}).json()
    assert client.post(f"/v1/offers/{second['id']}/acceptances", headers=headers, json=payload).status_code == 409
    with psycopg.connect(database_url()) as connection:
        connection.execute("UPDATE offers SET expires_at=now()-interval '1 second' WHERE id=%s", (second["id"],))
    payload["idempotency_key"] = str(uuid.uuid4())
    assert client.post(f"/v1/offers/{second['id']}/acceptances", headers=headers, json=payload).status_code == 409


def test_demo_research_does_not_spend_and_other_installation_cannot_access(client):
    headers, vehicle_id, _, _ = journey(client)
    response = client.post(f"/v1/vehicles/{vehicle_id}/research", headers=headers)
    assert response.json() == {"status": "demo", "cache_hit": True}
    other = installation(client)
    assert client.get(f"/v1/vehicles/{vehicle_id}/research", headers=other).status_code == 404


def test_booking_keeps_accepted_offer_and_updates_demo_schedule(client):
    headers, _, offer, _ = journey(client)
    payload = {"offer_version": 1, "idempotency_key": str(uuid.uuid4()), "payment_method": "vipps"}
    receipt = client.post(f"/v1/offers/{offer['id']}/acceptances", headers=headers, json=payload).json()
    assert receipt["offer"]["payment_method"] == "vipps"
    rows = client.get("/v1/bookings", headers=headers).json()["bookings"]
    assert len(rows) == 1 and rows[0]["state"] == "active"
    booking = rows[0]
    desired = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
    endpoint = f"/v1/bookings/{booking['id']}"
    assert client.patch(endpoint, headers=installation(client), json={"revision": 1, "appointment_at": desired}).status_code == 404
    assert client.patch(endpoint, headers=headers, json={"revision": 1, "appointment_at": desired}).status_code == 200
    assert client.patch(endpoint, headers=headers, json={"revision": 1, "appointment_at": desired}).status_code == 409
    updated = client.get("/v1/bookings", headers=headers).json()["bookings"][0]
    assert datetime.fromisoformat(updated["appointment_at"]) == datetime.fromisoformat(desired)
    assert updated["receipt"] == receipt
    assert client.patch(endpoint, headers=headers, json={"revision": 2, "state": "completed"}).status_code == 200
    assert client.patch(endpoint, headers=headers, json={"revision": 3, "appointment_at": desired}).status_code == 409
    assert client.get("/v1/bookings", headers=headers).json()["bookings"][0]["state"] == "completed"
    changed = {**payload, "payment_method": "apple_pay"}
    assert client.post(f"/v1/offers/{offer['id']}/acceptances", headers=headers, json=changed).status_code == 409


def test_provider_failure_preserves_original_source_and_identity(client, monkeypatch):
    plate = "ZZ00001"
    key = vehicle.lookup_key(plate)
    original = datetime.now(timezone.utc) - timedelta(days=3)
    facts = {"registration": plate, "make": "Example", "model": "Fixture", "source": "Statens vegvesen", "demo": False}
    with psycopg.connect(database_url()) as connection:
        connection.execute("INSERT INTO vehicle_cache (lookup_key,facts,source_retrieved_at) VALUES (%s,%s,%s)", (key, Jsonb(facts), original))
    monkeypatch.setenv("VEGVESEN_API_KEY", "synthetic-test-key")
    def timeout(*args, **kwargs):
        raise httpx.ReadTimeout("synthetic provider outage")
    monkeypatch.setattr(vehicle.httpx, "get", timeout)
    _, fallback = vehicle.get_vehicle_facts(plate)
    assert datetime.fromisoformat(fallback["fetched_at"]) == original
    assert fallback["cache_state"] == "stale_cache"
    assert fallback["registration"] == plate
    mismatch = {"kjoretoydataListe": [{"kjennemerke": [{"kjennemerke": "ZZ00002"}]}]}
    monkeypatch.setattr(vehicle.httpx, "get", lambda *a, **k: httpx.Response(200, json=mismatch, request=httpx.Request("GET", "https://example.invalid")))
    assert datetime.fromisoformat(vehicle.get_vehicle_facts(plate)[1]["fetched_at"]) == original
    with psycopg.connect(database_url()) as connection:
        assert connection.execute("SELECT facts FROM vehicle_cache WHERE lookup_key=%s", (key,)).fetchone()[0] == facts
