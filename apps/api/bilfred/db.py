"""One explicit migration authority; no schema push or startup DDL."""

import hashlib
import json
import os
from pathlib import Path

import psycopg

ROOT = Path(os.environ["BILFRED_ROOT"]) if os.environ.get("BILFRED_ROOT") else Path(__file__).resolve().parents[3]


def database_url() -> str:
    if value := os.environ.get("DATABASE_URL"):
        return value
    return json.loads((ROOT / ".local/database.json").read_text())["url"]


def migrate() -> None:
    with psycopg.connect(database_url()) as connection:
        connection.execute("SELECT pg_advisory_xact_lock(647283901)")
        connection.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations "
            "(name text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz "
            "NOT NULL DEFAULT now())"
        )
        for path in sorted((ROOT / "apps/api/migrations").glob("*.sql")):
            content = path.read_bytes()
            checksum = hashlib.sha256(content).hexdigest()
            applied = connection.execute(
                "SELECT sha256 FROM schema_migrations WHERE name = %s", (path.name,)
            ).fetchone()
            if applied:
                if applied[0] != checksum:
                    raise ValueError(f"Applied migration changed: {path.name}")
                continue
            connection.execute(content.decode())
            connection.execute(
                "INSERT INTO schema_migrations (name, sha256) VALUES (%s, %s)",
                (path.name, checksum),
            )
            print(f"Applied {path.name}")


if __name__ == "__main__":
    migrate()
