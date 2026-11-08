"""Small, versioned maintenance research cache. No overdue-work inference."""

import hashlib
import json
import calendar
from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, HttpUrl


class Guidance(BaseModel):
    service: Literal["service", "brakes", "tires"]
    title: str = Field(max_length=200)
    interval_km: int | None = Field(ge=1, le=500_000)
    interval_months: int | None = Field(ge=1, le=240)
    applicability: Literal["model_specific", "general", "unknown"]
    source_url: HttpUrl | None
    explanation: str = Field(max_length=3000)


class Research(BaseModel):
    guidance: list[Guidance] = Field(max_length=3)
    limitations: list[str] = Field(max_length=3)


class MaintenanceItem(BaseModel):
    id: Literal["oil_service", "inspection", "brake_fluid", "cabin_filter", "gearbox_service", "timing_belt", "brakes", "tires", "battery_check", "spark_plugs", "air_filter"]
    title: str = Field(max_length=80)
    summary: str = Field(max_length=180)
    why: str = Field(max_length=900)
    interval_km: int | None = Field(ge=1, le=500_000)
    interval_months: int | None = Field(ge=1, le=240)
    applicability: Literal["model_guidance", "general_guidance", "requires_variant_confirmation"]
    proposed_month_offset: int = Field(ge=0, le=24)
    proposal_reason: str = Field(max_length=400)
    source_url: HttpUrl
    source_title: str = Field(max_length=160)


class ResearchPlan(BaseModel):
    schema_version: Literal[2]
    items: list[MaintenanceItem] = Field(min_length=4, max_length=8)
    limitations: list[str] = Field(max_length=3)


def add_months(day: date, months: int) -> date:
    month_index = day.year * 12 + day.month - 1 + months
    year, month = divmod(month_index, 12)
    month += 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def proposed_events(research: dict, completed: set[str]) -> list[dict]:
    # Agent proposes relative planning windows. The application owns actual dates,
    # state and ordering; no agent output can create/override an EU deadline.
    anchor = date.fromisoformat(research["retrieved_at"][:10])
    return [{
        "id": item["id"], "title": item["title"], "subtitle": item["summary"],
        "kind": "proposal", "due_on": add_months(anchor, item["proposed_month_offset"]).isoformat(),
        "why": item["why"], "proposal_reason": item["proposal_reason"],
        "state": "recorded" if item["id"] in completed else "suggested",
        "guidance": [{"title": item["source_title"], "explanation": item["proposal_reason"],
                      "interval_km": item["interval_km"], "interval_months": item["interval_months"],
                      "source_url": item["source_url"]}],
        "applicability": item["applicability"], "research_retrieved_at": research["retrieved_at"],
    } for item in research["items"]]


def fingerprint(facts: dict) -> str:
    # Plate/VIN, current odometer and installation identity never leave the app's
    # vehicle domain. A different technical variant cannot inherit this research.
    context = {key: facts.get(key) for key in (
        "make", "model", "first_registered_on", "type_designation", "powertrain", "research_context"
    )}
    return hashlib.sha256(json.dumps(context, sort_keys=True).encode()).hexdigest()


def cached_guidance(connection, facts: dict) -> dict | None:
    row = connection.execute(
        "SELECT data,source_retrieved_at FROM maintenance_research WHERE fingerprint=%s",
        (fingerprint(facts),),
    ).fetchone()
    if not row:
        return None
    model = ResearchPlan if row["data"].get("schema_version") == 2 else Research
    data = model.model_validate(row["data"]).model_dump(mode="json")
    return {**data, "retrieved_at": row["source_retrieved_at"].isoformat(),
            "status": "needs_history_and_applicability_confirmation"}
