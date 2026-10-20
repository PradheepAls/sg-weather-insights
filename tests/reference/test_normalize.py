from datetime import datetime

import pytest

from reference.normalize import UpstreamError, normalise_region_payload, normalise_station_payload


def test_flattens_station_payload(fixture):
    stations, readings, token = normalise_station_payload(fixture("air_temperature_latest.json"))
    assert len(stations) == 4
    assert len(readings) == 4
    assert token is None
    s109 = next(r for r in readings if r.station_id == "S109")
    assert s109.value == 27.3
    assert s109.observed_at == datetime.fromisoformat("2026-10-20T16:03:00+08:00")


def test_returns_pagination_token_for_dated_queries(fixture):
    _, readings, token = normalise_station_payload(fixture("rainfall_by_date_page1.json"))
    assert token == "b2Zmc2V0PTI1"
    assert len(readings) == 5  # 2 + 3 across two timestamps


def test_skips_nulls_and_duplicates(fixture):
    _, readings, _ = normalise_station_payload(fixture("edge_duplicates_and_nulls.json"))
    assert [(r.station_id, r.value) for r in readings] == [("S109", 27.3)]


def test_unnamed_station_falls_back_to_id(fixture):
    stations, _, _ = normalise_station_payload(fixture("wind_speed_latest.json"))
    assert next(s for s in stations if s.station_id == "S199").name == "S199"


def test_error_envelope_raises(fixture):
    with pytest.raises(UpstreamError, match="Invalid date format"):
        normalise_station_payload(fixture("error_envelope.json"))


def test_region_payload_pivots_metrics_per_region(fixture):
    rows = normalise_region_payload(fixture("psi_latest.json"))
    assert [r.region for r in rows] == ["central", "east", "north", "south", "west"]
    west = next(r for r in rows if r.region == "west")
    assert west.metrics["psi_twenty_four_hourly"] == 114
    assert west.metrics["pm25_twenty_four_hourly"] == 68
