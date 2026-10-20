"""Reference for DGS_IS normalisation: raw data.gov.sg payload -> flat rows.

Mirrors DGS_IS.NormaliseStationPayload / NormaliseRegionPayload. The OutSystems BDD
integration tests assert the same row counts against the same fixtures.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


class UpstreamError(Exception):
    """Raised when the envelope reports an application error (code != 0)."""


@dataclass(frozen=True)
class StationRow:
    station_id: str
    name: str
    latitude: float
    longitude: float


@dataclass(frozen=True)
class ReadingRow:
    station_id: str
    observed_at: datetime
    value: float


@dataclass(frozen=True)
class RegionRow:
    region: str
    observed_at: datetime
    metrics: dict[str, float]


def _check_envelope(payload: dict) -> dict:
    if payload.get("code", -1) != 0:
        raise UpstreamError(payload.get("errorMsg") or f"code={payload.get('code')}")
    return payload["data"]


def normalise_station_payload(payload: dict) -> tuple[list[StationRow], list[ReadingRow], str | None]:
    """Returns stations, readings (deduplicated) and the next pagination token (or None)."""
    data = _check_envelope(payload)
    stations = [
        StationRow(s["id"], (s.get("name") or s["id"]).strip(), s["location"]["latitude"], s["location"]["longitude"])
        for s in data.get("stations", [])
    ]
    seen: set[tuple[str, datetime]] = set()
    readings: list[ReadingRow] = []
    for block in data.get("readings", []):
        ts = datetime.fromisoformat(block["timestamp"])
        for item in block.get("data", []):
            if item.get("value") is None:
                continue  # null readings are skipped, not stored as zero
            key = (item["stationId"], ts)
            if key in seen:
                continue  # upstream occasionally repeats a station within a timestamp
            seen.add(key)
            readings.append(ReadingRow(item["stationId"], ts, float(item["value"])))
    return stations, readings, data.get("paginationToken") or None


def normalise_region_payload(payload: dict) -> list[RegionRow]:
    data = _check_envelope(payload)
    rows: list[RegionRow] = []
    for item in data.get("items", []):
        ts = datetime.fromisoformat(item["timestamp"])
        regions = {r for metric in item["readings"].values() for r in metric}
        for region in sorted(regions):
            rows.append(RegionRow(region, ts, {m: v[region] for m, v in item["readings"].items() if region in v}))
    return rows
