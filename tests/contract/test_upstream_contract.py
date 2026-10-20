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

# The four station metrics the app stores (static entity Metric) and the PSI feed.
STATION_ENDPOINTS = {"air-temperature": "deg C", "relative-humidity": "percentage", "wind-speed": "knots", "rainfall": "mm"}
REGION_ENDPOINTS = ["psi"]

STATION_FIXTURES = ["air_temperature_latest.json", "relative_humidity_latest.json"]
EXPECTED_UNITS = {"air_temperature_latest.json": "deg C", "relative_humidity_latest.json": "percentage"}


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


def test_psi_carries_the_metrics_we_store(fixture):
    readings = fixture("psi_latest.json")["data"]["items"][0]["readings"]
    for key in ["psi_twenty_four_hourly", "pm25_twenty_four_hourly"]:
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
@pytest.mark.parametrize("endpoint,unit", STATION_ENDPOINTS.items())
def test_live_station_endpoint(endpoint, unit):
    body = _get(endpoint)
    errors = list(validator("station_readings").iter_errors(body))
    assert not errors, "\n".join(e.message for e in errors[:10])
    assert body["data"]["readingUnit"] == unit


@pytest.mark.live
@live
@pytest.mark.parametrize("endpoint", REGION_ENDPOINTS)
def test_live_region_endpoint(endpoint):
    errors = list(validator("region_readings").iter_errors(_get(endpoint)))
    assert not errors, "\n".join(e.message for e in errors[:10])
