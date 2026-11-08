"""Minimal consented waitlist, called only by Bilfred's web server."""
import os
import secrets
import uuid
from typing import Annotated, Literal

import psycopg
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from .db import database_url

router = APIRouter(prefix="/v1/waitlist", tags=["waitlist"])
CONSENT_VERSION = "2026-11-08"
CONSENT_TEXT = "Jeg vil få e-post om tidlig tilgang og lansering av Bilfred. Jeg kan trekke samtykket når som helst."


def authorize(x_waitlist_key: Annotated[str | None, Header()] = None):
    expected = os.environ.get("WAITLIST_API_KEY")
    if not expected:
        raise HTTPException(503, "Ventelisten er midlertidig utilgjengelig.")
    if not x_waitlist_key or not secrets.compare_digest(x_waitlist_key, expected):
        raise HTTPException(401, "Ikke autorisert.")


class Signup(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: EmailStr = Field(max_length=254)
    consent: Literal[True]
    consent_version: Literal["2026-11-08"]
    client_digest: str = Field(pattern=r"^[a-f0-9]{64}$")

    @field_validator("consent", mode="before")
    @classmethod
    def explicit_consent(cls, value):
        if value is not True:
            raise ValueError("Explicit consent is required")
        return value


def cleanup(connection):
    connection.execute("DELETE FROM waitlist_signups WHERE expires_at <= now()")
    connection.execute("DELETE FROM waitlist_rate_limits WHERE window_start < now() - interval '1 day'")


@router.post("", status_code=202, dependencies=[Depends(authorize)])
def signup(body: Signup):
    with psycopg.connect(database_url()) as connection:
        cleanup(connection)
        # One atomic transaction keeps concurrent limits and duplicates consistent.
        connection.execute("SELECT pg_advisory_xact_lock(647283902)")
        for bucket, limit in [("global", 200), (body.client_digest, 5)]:
            count = connection.execute("""INSERT INTO waitlist_rate_limits
                (bucket,window_start,requests) VALUES (%s,date_trunc('hour',now()),1)
                ON CONFLICT (bucket,window_start) DO UPDATE
                SET requests=waitlist_rate_limits.requests+1 RETURNING requests""",
                (bucket,)).fetchone()[0]
            if count > limit:
                raise HTTPException(429, "Prøv igjen om en stund.", headers={"Retry-After": "3600"})
        connection.execute("""INSERT INTO waitlist_signups
            (id,email,consent_version,consent_text) VALUES (%s,%s,%s,%s)
            ON CONFLICT (email) DO NOTHING""",
            (uuid.uuid4(), str(body.email).strip().lower(), CONSENT_VERSION, CONSENT_TEXT))
    # Same response for a new address and a repeat; no email enumeration.
    return {"accepted": True}


@router.post("/cleanup", dependencies=[Depends(authorize)])
def cleanup_expired():
    with psycopg.connect(database_url()) as connection:
        cleanup(connection)
    return {"ok": True}
