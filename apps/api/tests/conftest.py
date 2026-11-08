import uuid
import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from bilfred.app import app
from bilfred.db import database_url, migrate

@pytest.fixture
def client(monkeypatch):
    original = database_url()
    settings = conninfo_to_dict(original)
    if settings.get("host") not in ("127.0.0.1", "localhost") or settings.get("port") != "5448":
        pytest.fail("Integration tests require the dedicated local Bilfred PostgreSQL on port 5448")
    schema = "test_" + uuid.uuid4().hex
    with psycopg.connect(original) as connection:
        connection.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(schema)))
    monkeypatch.setenv("DATABASE_URL", make_conninfo(original, options=f"-c search_path={schema}"))
    migrate()
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        with psycopg.connect(original) as connection:
            connection.execute(sql.SQL("DROP SCHEMA {} CASCADE").format(sql.Identifier(schema)))
