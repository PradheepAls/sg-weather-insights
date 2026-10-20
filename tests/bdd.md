# BDD scenarios (implemented in OutSystems `Weather_Tests`)

```gherkin
Feature: SG Weather Insights core logic

  Scenario Outline: PSI bands follow NEA 24-hour thresholds
    Given a 24-hour PSI of <psi>
    When PsiBand is calculated
    Then the band is "<band>"
    Examples: see tests/vectors/psi_band.json (50 Good, 51 Moderate, 100 Moderate, 101 Unhealthy, 301 Hazardous)

  Scenario: Station payload is parsed
    Given the JSON in tests/contract/fixtures/air_temperature_latest.json
    When ParseStationJson runs
    Then 4 stations and 4 readings are returned
    And station S109 reads 27.3

  Scenario: PSI payload is parsed
    Given the JSON in tests/contract/fixtures/psi_latest.json
    When ParsePsiJson runs
    Then 5 regions are returned and west has PSI 114

  Scenario: An error envelope is a failure
    Given the JSON in tests/contract/fixtures/error_envelope.json
    When ParseStationJson runs
    Then IsSuccess is False and the message contains "Invalid date format"

  Scenario: Sync is idempotent
    When SyncMetric(AirTemperature) runs twice
    Then the second run adds 0 readings
```
