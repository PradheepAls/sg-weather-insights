"""Offline checks on the API contract itself (runs on every push)."""
from api.openapi_schema import assert_conforms, spec


def test_every_operation_has_an_operation_id_and_200():
    for path, ops in spec()["paths"].items():
        for method, op in ops.items():
            assert op.get("operationId"), f"{method.upper()} {path}"
            assert "200" in op["responses"], f"{method.upper()} {path}"


def test_error_responses_use_the_shared_envelope():
    for name in ("BadRequest", "NotFound"):
        schema = spec()["components"]["responses"][name]["content"]["application/json"]["schema"]
        assert schema == {"$ref": "#/components/schemas/Error"}


def test_sample_payloads_conform():
    assert_conforms(
        {"region": "west", "observedAt": "2026-10-19T20:00:00+08:00", "psi24h": 114,
         "psiBand": "Unhealthy", "psiLevel": 3, "pm25OneHour": None, "pm25Band": None},
        "AirQuality",
    )
    assert_conforms(
        {"status": "Degraded", "checkedAt": "2026-10-20T16:30:00+08:00",
         "endpoints": [{"endpoint": "pm25", "freshness": "NoData", "lastSuccessAt": None,
                        "lastRunStatus": "NeverRun", "latestObservedAt": None}]},
        "Health",
    )


def test_band_enum_matches_vectors(vectors):
    bands = {c["band"] for c in vectors("psi_band.json")["cases"]} - {"Invalid"}
    assert set(spec()["components"]["schemas"]["AirQuality"]["properties"]["psiBand"]["enum"]) == bands
