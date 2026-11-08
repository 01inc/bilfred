from decimal import Decimal
from math import asin, cos, exp, radians, sin, sqrt

import psycopg
from psycopg.rows import dict_row

from .db import database_url


def distance_km(area: dict, row: dict) -> float | None:
    if row.get("latitude") is None or row.get("longitude") is None:
        return None
    lat1, lat2 = radians(area["latitude"]), radians(row["latitude"])
    dlat = lat2 - lat1
    dlon = radians(row["longitude"] - area["longitude"])
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 6371 * 2 * asin(min(1, sqrt(a)))


def rank(rows: list[dict], area: dict) -> list[dict]:
    """Transparent demo rubric: reputation 50%, area proximity 30%, price 20%."""
    for row in rows:
        row["distance_km"] = distance_km(area, row)
    nearby = [r for r in rows if r["distance_km"] is not None and r["distance_km"] <= area.get("radius_km", 15)]
    pool = nearby if len(nearby) >= 3 else rows
    minimum = min((float(r["price_nok"]) for r in pool), default=1)
    for row in pool:
        reviews = row["review_count"]
        adjusted_rating = (float(row["rating"]) * reviews + 4.0 * 20) / (reviews + 20)
        reputation = max(0, min(1, (adjusted_rating - 3) / 2))
        location = exp(-row["distance_km"] / 10) if row["distance_km"] is not None else 0
        price = minimum / float(row["price_nok"])
        row["rubric_score"] = reputation * 0.5 + location * 0.3 + price * 0.2
    return sorted(pool, key=lambda r: (-r["rubric_score"], r["approval_id"]))[:3]


def service_options(area: dict, service: str) -> list[dict]:
    """Three complete demo cards; published facts are retained alongside overrides."""
    with psycopg.connect(database_url(), row_factory=dict_row) as connection:
        rows = connection.execute("""SELECT w.approval_id,w.name,w.address,w.postcode,w.city,w.latitude,w.longitude,
            e.price_nok,e.price_type,e.price_source_url,e.rating,e.review_count,e.rating_source_url
            FROM workshops w JOIN workshop_enrichments e USING (approval_id)
            WHERE w.active AND w.county_code='03' AND e.service='eu_kontroll'
            AND e.public_customers IS NOT FALSE AND e.price_nok > 0
            AND e.rating IS NOT NULL AND e.review_count >= 10
            ORDER BY w.approval_id""").fetchall()
    rows = rank(rows, area)
    # Oslo is the explicitly seeded demonstration area. Native MapKit resolves
    # these addresses; approximate distance is not fabricated by the server.
    choices = []
    labels = ["Anbefalt", "Et godt alternativ", "Et godt alternativ"]
    for i, row in enumerate(rows):
        price = int(Decimal(row["price_nok"]) * 100)
        if service != "eu_kontroll":
            price = {"service": 399000, "tires": 69000, "brakes": 99000, "oil_service": 249000,
                     "inspection": 399000, "brake_fluid": 149000, "cabin_filter": 89000,
                     "gearbox_service": 549000, "timing_belt": 129000, "battery_check": 49000,
                     "spark_plugs": 199000, "air_filter": 79000}[service] + i * 20000
        choices.append({
            "id": row["approval_id"], "name": row["name"].title(),
            "address": f"{row['address']}, {row['postcode']} {row['city']}",
            "price_ore": price, "currency": "NOK", "rating": float(row["rating"]),
            "review_count": row["review_count"], "label": labels[i],
            "price_source": "demo_offer", "reputation_source": "researched",
            "published_price_nok": float(row["price_nok"]),
            "published_price_type": row["price_type"],
            "published_price_url": row["price_source_url"],
            "rating_source_url": row["rating_source_url"],
            "latitude": row["latitude"], "longitude": row["longitude"],
            "distance_km": row["distance_km"],
            "selection_rubric": {"reputation": 0.5, "location": 0.3, "price": 0.2},
        })
    # Synthetic source fixtures only; no invented business reviews enter the cache.
    while len(choices) < 3:
        i = len(choices)
        choices.append({"id": f"demo-{i+1}", "name": f"Bilfred Demoverksted {i+1}",
                        "address": "Oslo · demonstrasjon", "price_ore": [129000, 109000, 149000][i],
                        "currency": "NOK", "rating": [4.8, 4.5, 4.9][i],
                        "review_count": [128, 86, 214][i], "label": labels[i],
                        "price_source": "demo_offer", "reputation_source": "demo",
                        "published_price_nok": None, "published_price_type": None,
                        "published_price_url": None, "rating_source_url": None,
                        "latitude": None, "longitude": None})
    return choices
