# Upstream stub

`docker compose -f tests/mocks/docker-compose.yml up` serves data.gov.sg-shaped responses on
port 8089. Scenarios are selected with the `X-Test-Scenario` header, which `DGS_IS` adds from
the `DGS_TestScenario` site property (empty, and therefore inert, outside Dev).
`wiremock/__files/` mirrors `tests/contract/fixtures/`; `make fixtures` refreshes both.

For the BDD integration suite, run the stub somewhere the Dev front-end can reach (for
example the WireMock standalone JAR on the Dev controller) and set the Dev-only site property
`DGS_BaseUrl` to it.
