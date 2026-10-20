# Review walkthrough

A 20-minute path through the solution, then the questions most likely to come up.

## Demo (≈ 12 min)

1. **Dashboard** (2 min) — switch Temperature → Humidity → Wind → Rain; point at the "as of"
   time and freshness badge. Click a marker → station detail.
2. **Station detail** (2 min) — 6 h raw vs 7 d hourly; mention the 48 h raw limit and why
   (point count, index range). Toggle "Show as table" (accessibility).
3. **Stations** (1 min) — search "changi", filter West, sort by temperature, reload: state is
   in the URL. Export CSV.
4. **Air quality** (1 min) — bands as text + icon, not colour alone; sub-index table.
5. **Admin** (2 min) — SyncRun history; "Sync now"; backfill yesterday's rainfall and show
   pages followed. Show `/health` JSON.
6. **Service Studio** (2 min) — module list in Architecture Canvas order; the `MERGE`
   Advanced SQL; `OnAfterResponse` turning 429 into data; timers.
7. **Pipeline + tests** (2 min) — GitHub Actions run: BDD on Dev → deploy Test → API/E2E
   → approval → Prod. Show a JUnit report with BDD step names matching the `.feature` files.

## Infrastructure (≈ 5 min)

* Two VPCs, why peering not TGW, why LifeTime sits in non-prod.
* One environment module, four var files, four states; preconditions that make an unsafe
  Prod plan fail; `terraform test` proving it without AWS.
* Secrets: ephemeral + write-only, RDS-managed master, `private.key` shared via Secrets
  Manager — the farm detail that usually breaks multi-server installs.
* Admin paths 403 on the public ALB; SSM instead of RDP.

## Likely questions

**Why not call data.gov.sg straight from the screens?**
Every user would multiply upstream calls and hit rate limits; an outage would blank the UI;
the API only returns the latest reading unless paged by date, so trends would need dozens of
calls. Ingestion gives one call per feed per five minutes and local history.

**How do you avoid duplicates if a sync runs twice or overlaps a backfill?**
Unique index on (station, metric, observed-at) and `MERGE`. Timers never run concurrently on
one environment; the index covers manual triggers.

**What if data.gov.sg changes its schema?**
Nightly live contract test against JSON Schemas opens a GitHub issue; normalisation is
isolated in `DGS_IS`, so the fix is one module; the UI keeps serving stored data meanwhile.

**Why OutSystems 11 and not ODC?**
The brief asks for IaC that deploys and operates the platform; ODC's runtime is SaaS and
cannot be provisioned on a customer's AWS account. The layering ports to ODC libraries/apps.

**How is this tested if OutSystems logic only runs inside the platform?**
Rules have shared vectors executed by BDD tests in the platform *and* by a Python reference
in CI, so expected values are verified twice. Integration tests use a WireMock stub for 429,
5xx, timeouts, error envelopes and pagination. The deployed API and UI are tested black-box.

**How would this scale?**
Reads hit indexed local tables and `LatestReading`; front-ends scale horizontally on CPU;
the API is cacheable for 60 s; the database is the shared component (Multi-AZ, vertical
scaling, Performance Insights). Ingestion volume is fixed by upstream cadence, not users.

**What did you deliberately leave out?**
Forecasts, user accounts/alerts, Amazon MQ for cache invalidation (not a documented
OutSystems configuration), automatic rotation of OutSystems DB logins (needs server
reconfiguration; runbook instead), shared non-prod database (cost lever, documented).
