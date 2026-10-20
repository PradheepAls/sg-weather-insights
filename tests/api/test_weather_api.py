"""Black-box tests against the deployed WeatherAPI.

    WEATHER_API_BASE_URL=https://<host>/Weather_CS/rest/WeatherAPI pytest -m integration
"""
import os
from datetime import datetime

import pytest
import requests

from api.openapi_schema import assert_conforms
from reference.weather_rules import psi_band

BASE = os.getenv("WEATHER_API_BASE_URL", "").rstrip("/")
METRICS = ["air-temperature", "relative-humidity", "wind-speed", "rainfall"]

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not BASE, reason="WEATHER_API_BASE_URL not set"),
]


def get(path, **params):
    return requests.get(f"{BASE}{path}", params=params, timeout=15)


@pytest.fixture(scope="module")
def station_id():
    stations = get("/stations", metric="air-temperature").json()["stations"]
    assert stations, "No data yet; has Timer_Sync run?"
    return stations[0]["id"]


@pytest.mark.parametrize("metric", METRICS)
def test_snapshot_is_valid_and_consistent(metric):
    r = get("/stations", metric=metric)
    assert r.status_code == 200
    body = r.json()
    assert_conforms(body, "Snapshot")
    values = [s["value"] for s in body["stations"]]
    assert values, f"no {metric} data"
    assert body["min"] == pytest.approx(min(values))
    assert body["max"] == pytest.approx(max(values))
    assert body["min"] <= body["avg"] <= body["max"]


def test_unknown_metric_is_400():
    assert get("/stations", metric="snowfall").status_code == 400


def test_series_is_ordered_oldest_first(station_id):
    r = get(f"/stations/{station_id}/readings", metric="air-temperature", hours=24)
    assert r.status_code == 200
    body = r.json()
    assert_conforms(body, "Point", array=True)
    times = [datetime.fromisoformat(p["observedAt"].replace("Z", "")) for p in body]
    assert times == sorted(times)


@pytest.mark.parametrize("hours", [0, 169])
def test_hours_out_of_range_is_400(station_id, hours):
    assert get(f"/stations/{station_id}/readings", metric="air-temperature", hours=hours).status_code == 400


def test_unknown_station_is_404():
    assert get("/stations/S99999/readings", metric="air-temperature").status_code == 404


def test_air_quality_has_five_regions_with_nea_bands():
    body = get("/air-quality").json()
    assert_conforms(body, "AirQuality", array=True)
    assert {r["region"] for r in body} == {"north", "south", "east", "west", "central"}
    for row in body:
        assert (row["band"], row["level"]) == psi_band(row["psi24h"]), row
