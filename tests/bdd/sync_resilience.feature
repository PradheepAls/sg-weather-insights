Feature: Sync resilience

  Background:
    Given DGS_IS points at the WireMock stub

  Scenario: 429 is retried with backoff then succeeds
    Given the stub returns 429 twice then fixture "air_temperature_latest.json" for air-temperature
    When SyncEndpoint("air-temperature") runs
    Then the stub received exactly 3 requests
    And a SyncRun is recorded with status Success

  Scenario: Persistent 5xx fails the endpoint without blocking the others
    Given the stub always returns 503 for psi
    And the stub returns fixture "air_temperature_latest.json" for air-temperature
    When SyncAllEndpoints runs
    Then the psi SyncRun has status Failed and HttpStatus 503
    And the air-temperature SyncRun has status Success

  Scenario: HTTP 200 with an error envelope is a failure
    Given the stub returns fixture "error_envelope.json" for rainfall
    When SyncEndpoint("rainfall") runs
    Then the rainfall SyncRun has status Failed and ErrorMessage containing "Invalid date format"
    And no Reading rows were written

  Scenario: Timeout is treated as a retryable failure
    Given the stub delays air-temperature responses by 20 seconds
    When SyncEndpoint("air-temperature") runs
    Then a SyncRun is recorded with status Failed and ErrorMessage containing "timeout"

  Scenario: Consecutive failures surface in health
    Given 3 consecutive failed SyncRuns for psi
    When GetHealth is called
    Then psi reports consecutiveFailures 3
    And the overall status is Degraded

  Scenario: The API key is sent only when configured
    Given the DGS_ApiKey site property is "test-key"
    When SyncEndpoint("air-temperature") runs
    Then the stub received header "x-api-key: test-key"
    And the key does not appear in the integration log
