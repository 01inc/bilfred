from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

Service = Literal["eu_kontroll", "service", "tires", "brakes", "oil_service", "inspection",
                  "brake_fluid", "cabin_filter", "gearbox_service", "timing_belt", "battery_check",
                  "spark_plugs", "air_filter"]


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid")


class VehicleLookup(Input):
    registration: str = Field(min_length=1, max_length=20)
    demo: bool = False


class MileageInput(Input):
    km: int = Field(ge=0, le=3_000_000)
    observed_on: date


class HistoryInput(Input):
    service: Service
    completed_on: date | None = None
    km: int | None = Field(default=None, ge=0, le=3_000_000)


class Area(Input):
    name: str = Field(min_length=1, max_length=100)
    postcode: str | None = Field(default=None, pattern=r"^\d{4}$")
    # These are area centroids, never precise device coordinates.
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    radius_km: float = Field(default=15, ge=1, le=100)


class ServiceSearch(Input):
    vehicle_id: UUID
    service: Service = "eu_kontroll"
    area: Area
    mode: Literal["demo"] = "demo"


class OfferInput(ServiceSearch):
    option_id: str = Field(min_length=1, max_length=40)
    appointment_at: AwareDatetime | None = None


class AcceptInput(Input):
    offer_version: int = Field(ge=1)
    idempotency_key: UUID
    payment_method: Literal["apple_pay", "vipps"] = "apple_pay"


class BookingUpdate(Input):
    revision: int = Field(ge=1)
    appointment_at: AwareDatetime | None = None
    state: Literal["active", "completed"] | None = None
