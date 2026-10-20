"""Reference implementation of WeatherRules_Lib.

This is NOT the production implementation (that lives in the OutSystems Library module).
It exists so the shared vectors in tests/vectors/ are executable and self-consistent: if a
vector is wrong, this suite fails in CI before anyone codes it into a BDD test.
Each function mirrors one public Server/Client Action in WeatherRules_Lib with the same name.
"""
from __future__ import annotations

import math
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

PSI_BANDS = [(50, "Good", 1), (100, "Moderate", 2), (200, "Unhealthy", 3), (300, "Very unhealthy", 4)]
PM25_BANDS = [(55, "Normal", 1), (150, "Elevated", 2), (250, "High", 3)]
COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
           "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def psi_band(psi: int) -> tuple[str, int]:
    if psi < 0:
        return "Invalid", 0
    for upper, name, level in PSI_BANDS:
        if psi <= upper:
            return name, level
    return "Hazardous", 5


def pm25_band(pm25: int) -> tuple[str, int]:
    if pm25 < 0:
        return "Invalid", 0
    for upper, name, level in PM25_BANDS:
        if pm25 <= upper:
            return name, level
    return "Very high", 4


def compass_point(degrees: float) -> str:
    normalised = degrees % 360
    return COMPASS[int((normalised + 11.25) // 22.5) % 16]


def _round1(value: float) -> float:
    return float(Decimal(str(value)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def knots_to_kmh(knots: float) -> float:
    return _round1(knots * 1.852)


def knots_to_ms(knots: float) -> float:
    return _round1(knots * 0.514444)


def freshness(latest: datetime | None, now: datetime, threshold_minutes: int) -> str:
    if latest is None:
        return "NoData"
    age_seconds = (now - latest).total_seconds()
    return "Fresh" if age_seconds <= threshold_minutes * 60 else "Stale"


def _haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(h))


def nearest_region(lat: float, lon: float, regions: dict[str, tuple[float, float]]) -> str:
    return min(regions, key=lambda name: _haversine_km((lat, lon), tuple(regions[name])))
