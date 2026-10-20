Feature: Normalising and storing data.gov.sg readings (DGS_IS + Weather_CS)

  Background:
    Given DGS_IS points at the WireMock stub
    And no test data exists for the current TestRunId

  Scenario: Station payload is flattened into readings
    Given the stub returns fixture "air_temperature_latest.json" for air-temperature
    When SyncEndpoint("air-temperature") runs
    Then 4 stations exist
    And 4 Reading rows exist for metric AirTemperature
    And LatestReading for S109 AirTemperature is 27.3 observed at 2026-10-20T16:03:00+08:00
    And a SyncRun is recorded with status Success and RowsUpserted 4

  Scenario: Re-running a sync is idempotent
    Given the stub returns fixture "air_temperature_latest.json" for air-temperature
    When SyncEndpoint("air-temperature") runs twice
    Then 4 Reading rows exist for metric AirTemperature

  Scenario: Nulls and duplicate stations are tolerated
    Given the stub returns fixture "edge_duplicates_and_nulls.json" for air-temperature
    When SyncEndpoint("air-temperature") runs
    Then 1 Reading row exists for metric AirTemperature
    And no Reading row exists for S24

  Scenario: Stations without a name fall back to their ID
    Given the stub returns fixture "wind_speed_latest.json" for wind-speed
    When SyncEndpoint("wind-speed") runs
    Then station S199 has name "S199"
    And station S199 is assigned to the nearest region

  Scenario: Backfill follows pagination tokens until exhausted
    Given the stub returns "rainfall_by_date_page1.json" for rainfall on 2026-10-14
    And the stub returns a final page without paginationToken for token "b2Zmc2V0PTI1"
    When Backfill("rainfall", 2026-10-14) runs
    Then the stub received exactly 2 requests for rainfall
    And the second request carried paginationToken "b2Zmc2V0PTI1"

  Scenario: Regional payload is pivoted per region
    Given the stub returns fixture "psi_latest.json" for psi
    When SyncEndpoint("psi") runs
    Then 5 AirQualityReading rows exist observed at 2026-10-19T20:00:00+08:00
    And the west row has Psi24h 114 and Pm25_24h 68

  Scenario: Hourly rollup aggregates raw readings
    Given readings 28.0, 29.0 and 30.0 for S109 AirTemperature within 2026-10-20 15:00-15:59
    When Timer_Rollup runs for hour 2026-10-20 15:00
    Then HourlyAggregate for that hour has min 28.0, max 30.0, avg 29.0 and count 3

  Scenario: Retention purges raw readings older than 7 days but keeps aggregates
    Given a Reading and an HourlyAggregate dated 8 days ago
    When Timer_Purge runs
    Then the Reading is deleted
    And the HourlyAggregate remains
