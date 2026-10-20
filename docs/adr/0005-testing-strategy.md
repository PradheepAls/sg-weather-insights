# ADR 0005 — Testing strategy

**Status:** Accepted

| Layer | Tool | Runs | What it proves |
|---|---|---|---|
| Upstream contract | pytest + JSON Schema on recorded fixtures; same schemas against live API nightly | every push / nightly | Our assumptions about data.gov.sg still hold; drift is caught before users see it |
| Business rules | BDD Framework (server + client) driven by `tests/vectors/*.json`; Python reference over the same vectors | every LifeTime tag / every push | Banding, freshness, unit and direction rules are correct at the edges |
| Integration | BDD Framework scenarios in `Weather_Tests` with a stubbed `DGS_IS` base URL (WireMock) | every LifeTime tag | Normalisation, MERGE idempotency, error handling, retry on 429 |
| API | pytest + OpenAPI schema validation against the deployed `Weather_API` | after deploy to Test | Public contract and error envelope |
| UI / E2E | Playwright + axe-core | after deploy to Test | Critical journeys and WCAG AA regressions |
| Load | k6 smoke | on demand | p95 latency of snapshot and series endpoints |
| IaC | `terraform test` with mock providers, tflint, Checkov | every push | Security and environment-specific invariants without AWS credentials |

Trade-off: OutSystems logic is only testable inside the platform, so BDD tests run in the Dev
or Test environment via the CI/CD Probe rather than in a container. Everything outside the
platform runs offline in CI.
