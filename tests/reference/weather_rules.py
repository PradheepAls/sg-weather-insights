"""Reference implementation of Weather_CS.PsiBand.

Not the production code (that lives in OutSystems). It makes tests/vectors/psi_band.json
executable, so the expected values used by the OutSystems BDD test and the API test are
checked once here in CI.
"""

PSI_BANDS = [(50, "Good", 1), (100, "Moderate", 2), (200, "Unhealthy", 3), (300, "Very unhealthy", 4)]


def psi_band(psi: int) -> tuple[str, int]:
    if psi < 0:
        return "Invalid", 0
    for upper, name, level in PSI_BANDS:
        if psi <= upper:
            return name, level
    return "Hazardous", 5
