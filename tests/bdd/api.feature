Feature: Weather_API contract (server-side, before deployment)
  Complements tests/api, which runs the same contract black-box after deployment.

  Scenario: Raw series window is limited to 48 hours
    When GetStationSeries is called with interval raw for a 49 hour window
    Then the response status is 400 with code "INVALID_RANGE"

  Scenario: Hourly series switches source table
    Given HourlyAggregate rows for the last 3 days for a test station
    When GetStationSeries is called with interval hour for 3 days
    Then 72 points are returned ordered oldest first

  Scenario: Snapshot statistics
    Given latest air temperatures 27.0, 29.0 and 31.0 at three test stations
    When GetSnapshot is called for air-temperature
    Then min is 27.0, max is 31.0, avg is 29.0 and stationCount is 3
