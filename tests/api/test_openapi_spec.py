"""Offline checks on the API contract itself (runs on every push)."""
from api.openapi_schema import assert_conforms, spec


def test_every_operation_has_an_operation_id_and_200():
    for path, ops in spec()["paths"].items():
        for method, op in ops.items():
            assert op.get("operationId"), f"{method.upper()} {path}"
            assert "200" in op["responses"], f"{method.upper()} {path}"


def test_sample_payloads_conform():
    assert_conforms(
        {"metric": "air-temperature", "unit": "°C", "asOf": "2026-10-20T16:03:00", "min": 27.3, "avg": 28.7,
         "max": 30.0, "stations": [{"id": "S109", "name": "Ang Mo Kio Avenue 5", "value": 27.3}]},
        "Snapshot",
    )
    assert_conforms(
        {"region": "west", "observedAt": "2026-10-19T20:00:00", "psi24h": 114, "pm25_24h": 68,
         "band": "Unhealthy", "level": 3},
        "AirQuality",
    )


def test_band_enum_matches_vectors(vectors):
    bands = {c["band"] for c in vectors("psi_band.json")["cases"]} - {"Invalid"}
    assert set(spec()["components"]["schemas"]["AirQuality"]["properties"]["band"]["enum"]) == bands
