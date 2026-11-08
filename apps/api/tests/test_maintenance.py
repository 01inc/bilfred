from datetime import date

from bilfred.maintenance import add_months, proposed_events
from bilfred.options import rank


def test_calendar_planning_is_stable_and_does_not_create_eu_deadlines():
    assert add_months(date(2026, 1, 31), 1) == date(2026, 2, 28)
    research = {"retrieved_at": "2026-11-08T10:00:00Z", "items": [{
        "id": "oil_service", "title": "Oljeservice", "summary": "Sjekk historikken",
        "why": "Foreslått kontroll", "proposed_month_offset": 4, "proposal_reason": "Planpunkt",
        "source_title": "Synthetic source", "interval_km": 15000, "interval_months": 12,
        "source_url": "https://example.com/service", "applicability": "requires_variant_confirmation",
    }]}
    events = proposed_events(research, {"oil_service"})
    assert events[0]["due_on"] == "2027-03-08"
    assert events[0]["kind"] == "proposal"
    assert events[0]["state"] == "recorded"
    assert all(e["id"] != "eu_kontroll" for e in events)


def test_shortlist_uses_reputation_distance_and_price():
    area = {"latitude": 59.91, "longitude": 10.75, "radius_km": 15}
    base = {"rating": 4.6, "review_count": 100, "latitude": 59.91, "longitude": 10.75, "price_nok": 1500}
    rows = [
        {**base, "approval_id": "near-fair"},
        {**base, "approval_id": "near-low-price", "price_nok": 990},
        {**base, "approval_id": "near-high-reputation", "rating": 4.9, "review_count": 300},
        {**base, "approval_id": "distant", "latitude": 60.5, "price_nok": 100},
    ]
    chosen = rank(rows, area)
    assert len(chosen) == 3
    assert "distant" not in {r["approval_id"] for r in chosen}
    assert chosen[0]["approval_id"] in ("near-low-price", "near-high-reputation")
    assert chosen[-1]["approval_id"] == "near-fair"
