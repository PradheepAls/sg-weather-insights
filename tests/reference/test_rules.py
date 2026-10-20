"""Executes the shared vectors against the reference rules.

The OutSystems BDD suite (Weather_Tests / Weather_ClientTests) consumes the same JSON files,
so this test guarantees the expected values are internally consistent.
"""
from datetime import datetime

import pytest

from reference import weather_rules as r


def test_psi_band(vectors):
    for c in vectors("psi_band.json")["cases"]:
        assert r.psi_band(c["psi"]) == (c["band"], c["level"]), c


def test_pm25_band(vectors):
    for c in vectors("pm25_band.json")["cases"]:
        assert r.pm25_band(c["pm25"]) == (c["band"], c["level"]), c


def test_compass(vectors):
    for c in vectors("compass.json")["cases"]:
        assert r.compass_point(c["degrees"]) == c["point"], c


def test_units(vectors):
    for c in vectors("units.json")["cases"]:
        assert r.knots_to_kmh(c["knots"]) == c["kmh"], c
        assert r.knots_to_ms(c["knots"]) == c["ms"], c


def test_freshness(vectors):
    v = vectors("freshness.json")
    now = datetime.fromisoformat(v["now"])
    for c in v["cases"]:
        latest = datetime.fromisoformat(c["latest"]) if c["latest"] else None
        assert r.freshness(latest, now, v["thresholds"][c["endpoint"]]) == c["status"], c


def test_nearest_region(vectors):
    v = vectors("nearest_region.json")
    for c in v["cases"]:
        assert r.nearest_region(c["lat"], c["lon"], v["regions"]) == c["region"], c


@pytest.mark.parametrize("bad", [float("nan")])
def test_compass_rejects_nan(bad):
    with pytest.raises(ValueError):
        r.compass_point(bad)
