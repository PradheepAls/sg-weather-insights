Feature: Weather rules (WeatherRules_Lib)
  The same rules colour the map client-side and band the API responses server-side.

  Scenario Outline: PSI is banded using NEA 24-hour PSI thresholds
    Given a 24-hour PSI of <psi>
    When the PSI band is calculated
    Then the band is "<band>" at level <level>
    # cases: tests/vectors/psi_band.json

  Scenario Outline: PM2.5 is banded using NEA 1-hour thresholds
    Given a 1-hour PM2.5 concentration of <pm25>
    When the PM2.5 band is calculated
    Then the band is "<band>" at level <level>
    # cases: tests/vectors/pm25_band.json

  Scenario Outline: Wind direction is shown as a 16-point compass
    Given a wind direction of <degrees> degrees
    When it is converted to a compass point
    Then the compass point is "<point>"
    # cases: tests/vectors/compass.json

  Scenario Outline: Wind speed is converted from knots
    Given a wind speed of <knots> knots
    When it is converted
    Then it is <kmh> km/h and <ms> m/s rounded to one decimal place
    # cases: tests/vectors/units.json

  Scenario Outline: Freshness uses per-endpoint thresholds
    Given the newest <endpoint> reading was observed at <latest>
    And the time is now 2026-10-20T16:30:00+08:00
    When freshness is evaluated
    Then the status is "<status>"
    # cases: tests/vectors/freshness.json
