import psycopg
from bilfred.db import database_url
from bilfred.waitlist import CONSENT_TEXT


def test_waitlist_validation_consent_and_duplicate(client, monkeypatch):
    monkeypatch.setenv("WAITLIST_API_KEY", "synthetic-test-key")
    headers = {"X-Waitlist-Key": "synthetic-test-key"}
    body = {"email": "Interested@Example.com", "consent": True,
            "consent_version": "2026-11-08", "client_digest": "a" * 64}
    assert client.post("/v1/waitlist", json=body).status_code == 401
    for changes in [{"email": "invalid"}, {"consent": False}, {"consent": 1}, {"consent": "true"}, {"consent_version": "old"}]:
        assert client.post("/v1/waitlist", headers=headers, json={**body, **changes}).status_code == 422
    assert client.post("/v1/waitlist", headers=headers, json=body).status_code == 202
    assert client.post("/v1/waitlist", headers=headers, json={**body, "email": "interested@example.com"}).json() == {"accepted": True}
    with psycopg.connect(database_url()) as db:
        rows = db.execute("SELECT email,consent_text,consented_at,expires_at FROM waitlist_signups").fetchall()
        assert len(rows) == 1 and rows[0][0] == "interested@example.com"
        assert rows[0][1] == CONSENT_TEXT and rows[0][3] > rows[0][2]
    for _ in range(3):
        assert client.post("/v1/waitlist", headers=headers, json=body).status_code == 202
    assert client.post("/v1/waitlist", headers=headers, json=body).status_code == 429


def test_waitlist_retention_cleanup_requires_auth(client, monkeypatch):
    monkeypatch.setenv("WAITLIST_API_KEY", "synthetic-test-key")
    headers = {"X-Waitlist-Key": "synthetic-test-key"}
    body = {"email": "expired@example.com", "consent": True,
            "consent_version": "2026-11-08", "client_digest": "b" * 64}
    client.post("/v1/waitlist", headers=headers, json=body)
    with psycopg.connect(database_url()) as db:
        db.execute("UPDATE waitlist_signups SET expires_at=now()-interval '1 day'")
    assert client.post("/v1/waitlist/cleanup").status_code == 401
    assert client.post("/v1/waitlist/cleanup", headers=headers).status_code == 200
    with psycopg.connect(database_url()) as db:
        assert db.execute("SELECT count(*) FROM waitlist_signups").fetchone()[0] == 0
