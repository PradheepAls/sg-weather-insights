"""Black-box tests against a deployed Weather_API (Test environment in the pipeline).

    WEATHER_API_BASE_URL=https://<host>/Weather_API/rest/v1 pytest -m integration
"""
import os
from datetime import datetime, timedelta, timezone

import pytest
import requests

from api.openapi_schema import assert_conforms
from reference.weather_rules import psi_band

BASE = os.getenv("WEATHER_API_BASE_URL", "").rstrip("/")
SGT = timezone(timedelta(hours=8))
REGIONS = {"north", "south", "east", "west", "central"}
ENDPOINTS = {"air-temperature", "relative-humidity", "wind-speed", "wind-direction", "rainfall", "psi", "pm25"}

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not BASE, reason="WEATHER_API_BASE_URL not set"),
]


def get(path, **params):
    return requests.get(f"{BASE}{path}", params=params, timeout=15)


def iso(dt):
    return dt.isoformat(timespec="seconds")


@pytest.fixture(scope="module")
def any_station():
    body = get("/stations", metric="air-temperature", pageSize=1).json()
    assert body["items"], "Test environment has no ingested stations; is Timer_SyncRealtime running?"
    return body["items"][0]["id"]


def test_health_lists_every_upstream_endpoint():
    r = get("/health")
    assert r.status_code == 200
    body = r.json()
    assert_conforms(body, "Health")
    assert {e["endpoint"] for e in body["endpoints"]} == ENDPOINTS
    degraded = any(e["freshness"] != "Fresh" for e in body["endpoints"])
    assert body["status"] == ("Degraded" if degraded else "Healthy")


def test_metrics():
    r = get("/metrics")
    assert_conforms(r.json(), "Metric", array=True)
    assert {m["code"] for m in r.json()} == ENDPOINTS - {"psi", "pm25"}


def test_responses_are_cacheable():
    assert "max-age=60" in get("/snapshot", metric="air-temperature").headers.get("Cache-Control", "")


def test_station_paging_is_stable_and_disjoint():
    p1 = get("/stations", page=1, pageSize=5).json()
    p2 = get("/stations", page=2, pageSize=5).json()
    assert_conforms(p1, "StationPage")
    assert p1["total"] == p2["total"] and p1["total"] >= 6
    assert not {s["id"] for s in p1["items"]} & {s["id"] for s in p2["items"]}


def test_region_and_text_filters():
    west = get("/stations", region="west", pageSize=100).json()["items"]
    assert west and all(s["region"] == "west" for s in west)
    hits = get("/stations", q="changi", pageSize=100).json()["items"]
    assert hits and all("changi" in s["name"].lower() or "changi" in s["id"].lower() for s in hits)


def test_invalid_metric_is_400_with_error_envelope():
    r = get("/stations", metric="snowfall")
    assert r.status_code == 400
    assert_conforms(r.json(), "Error")


def test_unknown_station_is_404():
    r = get("/stations/S99999")
    assert r.status_code in (400, 404)  # 400 if the path pattern check fires first
    assert_conforms(r.json(), "Error")


def test_raw_series_is_ordered_and_within_range(any_station):
    to = datetime.now(SGT)
    frm = to - timedelta(hours=6)
    r = get(f"/stations/{any_station}/readings", metric="air-temperature", **{"from": iso(frm), "to": iso(to)})
    assert r.status_code == 200
    body = r.json()
    assert_conforms(body, "Series")
    ts = [datetime.fromisoformat(p["t"]) for p in body["points"]]
    assert ts == sorted(ts)
    assert all(frm - timedelta(minutes=1) <= t <= to + timedelta(minutes=1) for t in ts)


def test_raw_series_rejects_windows_over_48h(any_station):
    to = datetime.now(SGT)
    r = get(f"/stations/{any_station}/readings", metric="air-temperature",
            **{"from": iso(to - timedelta(hours=49)), "to": iso(to), "interval": "raw"})
    assert r.status_code == 400 and r.json()["code"] == "INVALID_RANGE"


def test_inverted_range_is_rejected(any_station):
    to = datetime.now(SGT)
    r = get(f"/stations/{any_station}/readings", metric="air-temperature",
            **{"from": iso(to), "to": iso(to - timedelta(hours=1))})
    assert r.status_code == 400


def test_hourly_series_points_carry_min_max(any_station):
    to = datetime.now(SGT)
    body = get(f"/stations/{any_station}/readings", metric="air-temperature",
               **{"from": iso(to - timedelta(days=3)), "to": iso(to), "interval": "hour"}).json()
    for p in body["points"]:
        assert p["min"] <= p["value"] <= p["max"] and p["count"] >= 1


@pytest.mark.parametrize("metric", ["air-temperature", "relative-humidity", "wind-speed", "rainfall"])
def test_snapshot_statistics_are_consistent(metric):
    body = get("/snapshot", metric=metric).json()
    assert_conforms(body, "Snapshot")
    values = [s["value"] for s in body["stations"]]
    stats = body["stats"]
    assert stats["stationCount"] == len(values)
    assert stats["min"] == min(values) and stats["max"] == max(values)
    assert stats["min"] <= stats["avg"] <= stats["max"]


def test_air_quality_bands_follow_nea_rules():
    body = get("/air-quality/latest").json()
    assert_conforms(body, "AirQuality", array=True)
    assert {r["region"] for r in body} == REGIONS
    for row in body:
        assert (row["psiBand"], row["psiLevel"]) == psi_band(row["psi24h"]), row
