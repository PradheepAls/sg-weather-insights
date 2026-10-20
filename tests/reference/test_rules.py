from reference.weather_rules import psi_band


def test_psi_band_vectors(vectors):
    for case in vectors("psi_band.json")["cases"]:
        assert psi_band(case["psi"]) == (case["band"], case["level"]), case
