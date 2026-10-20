# BDD scenarios (OutSystems BDD Framework)

These `.feature` files are the specification for the tests implemented inside the
OutSystems test application (`SG Weather Insights Tests`):

| Feature file | OutSystems module | Framework | Screen per feature |
|---|---|---|---|
| `rules.feature` | `Weather_ClientTests` | BDDFramework client-side | `RulesTests` |
| `ingestion.feature` | `Weather_Tests` | BDDFramework (server) | `IngestionTests` |
| `sync_resilience.feature` | `Weather_Tests` | BDDFramework (server) | `SyncResilienceTests` |
| `api.feature` | `Weather_Tests` | BDDFramework (server) | `ApiContractTests` |

Conventions:

* One BDD screen per feature, one `BDDScenario` block per scenario, step names copied verbatim
  so failures in the pipeline's JUnit report map straight back to this file.
* Data-driven scenarios load cases from `tests/vectors/*.json`. The JSON is embedded in the
  test module as a Resource (refreshed when vectors change) and parsed with
  `JSONDeserialize` into a list, so the expected values are reviewed once in Git.
* Integration scenarios point `DGS_IS` at the WireMock stub (`tests/mocks/wiremock`) by
  overriding the consumed REST API base URL through the `DGS_BaseUrl` site property in the
  Dev environment only. Each scenario resets WireMock scenario state in its `Setup` step.
* Tests that write data use `TestRunId` (a GUID) as a station-ID prefix and delete their rows in
  `Teardown`, so runs are repeatable and never touch real ingested data.

The pipeline discovers and runs these screens through the CI/CD Probe
(`outsystems.pipeline.generate_unit_testing_assembly` → `evaluate_test_results`).
