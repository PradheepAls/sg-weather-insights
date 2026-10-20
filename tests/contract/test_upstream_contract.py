"""Contract tests for data.gov.sg.

Offline (default): validate recorded fixtures, so a schema change in this repo is reviewed
against real shapes. Live (`pytest -m live`, nightly in CI): hit the real API with the same
schemas so upstream drift is caught before it breaks ingestion.
"""
import json
import os
from pathlib import Path

import pytest
import requests
from jsonschema import Draft202012Validator

SCHEMAS = Path(__file__).parent / "schemas"
BASE = "https://api-open.data.gov.sg/v2/real-time/api"

STATION_ENDPOINTS = ["air-temperature", "relative-humidity", "wind-speed", "wind-direction", "rainfall"]
REGION_ENDPOINTS = ["psi", "pm25"]

STATION_FIXTURES = [
    "air_temperature_latest.json",
    "relative_humidity_latest.json",
    "wind_speed_latest.json",
    "rainfall_by_date_page1.json",
    "edge_duplicates_and_nulls.json",
]
EXPECTED_UNITS = {
    "air_temperature_latest.json": "deg C",
    "relative_humidity_latest.json": "percentage",
    "wind_speed_latest.json": "knots",
    "rainfall_by_date_page1.json": "mm",
}


def validator(name: str) -> Draft202012Validator:
    return Draft202012Validator(json.loads((SCHEMAS / f"{name}.schema.json").read_text()))


@pytest.mark.parametrize("name", STATION_FIXTURES)
def test_station_fixtures_match_schema(fixture, name):
    errors = sorted(validator("station_readings").iter_errors(fixture(name)), key=str)
    assert not errors, "\n".join(e.message for e in errors)


def test_region_fixture_matches_schema(fixture):
    errors = list(validator("region_readings").iter_errors(fixture("psi_latest.json")))
    assert not errors, "\n".join(e.message for e in errors)


@pytest.mark.parametrize("name,unit", EXPECTED_UNITS.items())
def test_units_are_what_the_ui_assumes(fixture, name, unit):
    # Unit changes upstream would silently mislabel every chart; fail loudly instead.
    assert fixture(name)["data"]["readingUnit"] == unit


def test_psi_carries_all_metrics_we_store(fixture):
    readings = fixture("psi_latest.json")["data"]["items"][0]["readings"]
    for key in ["psi_twenty_four_hourly", "pm25_twenty_four_hourly", "pm10_twenty_four_hourly",
                "o3_eight_hour_max", "no2_one_hour_max", "so2_twenty_four_hourly", "co_eight_hour_max"]:
        assert set(readings[key]) == {"north", "south", "east", "west", "central"}, key


def test_error_envelope_is_rejected_by_schema(fixture):
    assert list(validator("station_readings").iter_errors(fixture("error_envelope.json")))


# ---------------------------------------------------------------- live (nightly)

live = pytest.mark.skipif(os.getenv("DGS_LIVE") != "1", reason="set DGS_LIVE=1 to call data.gov.sg")


def _get(endpoint: str, **params):
    headers = {"x-api-key": os.environ["DGS_API_KEY"]} if os.getenv("DGS_API_KEY") else {}
    resp = requests.get(f"{BASE}/{endpoint}", params=params, headers=headers, timeout=20)
    resp.raise_for_status()
    return resp.json()


@pytest.mark.live
@live
@pytest.mark.parametrize("endpoint", STATION_ENDPOINTS)
def test_live_station_endpoint(endpoint):
    errors = list(validator("station_readings").iter_errors(_get(endpoint)))
    assert not errors, "\n".join(e.message for e in errors[:10])


@pytest.mark.live
@live
@pytest.mark.parametrize("endpoint", REGION_ENDPOINTS)
def test_live_region_endpoint(endpoint):
    errors = list(validator("region_readings").iter_errors(_get(endpoint)))
    assert not errors, "\n".join(e.message for e in errors[:10])


@pytest.mark.live
@live
def test_live_pagination_token_round_trips():
    from datetime import date, timedelta

    day = (date.today() - timedelta(days=1)).isoformat()
    first = _get("rainfall", date=day)
    token = first["data"].get("paginationToken")
    assert token, "a full past day of rainfall should span more than one page"
    second = _get("rainfall", date=day, paginationToken=token)
    t1 = {r["timestamp"] for r in first["data"]["readings"]}
    t2 = {r["timestamp"] for r in second["data"]["readings"]}
    assert t1.isdisjoint(t2), "page 2 must not repeat page 1"
