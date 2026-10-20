# OutSystems build guide

Implementation spec for the OutSystems 11 modules. Build in the order below; each step lists
what to create and the decision behind anything non-obvious. Names are exact, because the
tests, pipeline and docs refer to them.

## 0. Prerequisites

| Item | Value |
|---|---|
| Platform | OutSystems 11 (Platform Server 11.2x or later), Reactive Web |
| Forge | `OutSystems UI` (bundled), `OutSystems Charts` (bundled), `OutSystems Maps` (Leaflet provider, no API key needed), `BDDFramework`, `BDDFramework Client Side`, `CI/CD Probe` (for the pipeline), `HTTPRequestHandler` (system) |
| Applications | **SG Weather Insights** (all runtime modules) and **SG Weather Insights Tests** (test modules, marked as test app in the pipeline manifest, never deployed to Prod) |
| Time zone | All `DateTime` attributes hold **server-local** time. On the AWS factory servers run in `Singapore Standard Time` so server-local = SGT. On a factory whose servers run in UTC, set site property `SgtOffsetFromServerHours = 8`. Singapore has no DST, so a fixed offset is exact. |

## 1. `Theme_Weather` (Foundation, Theme)

* Based on OutSystems UI. Define CSS custom properties for the palette and the five PSI band
  colours (`--band-1` … `--band-5`) and four PM2.5 band colours, each with a dark-mode value
  under `@media (prefers-color-scheme: dark)`. Text on band backgrounds must reach 4.5:1.
* Layout: `LayoutTopMenu`; menu entries Dashboard, Stations, Air quality, Admin (visible to
  `WeatherAdmin` only).
* Footer (required by the Singapore Open Data Licence v1.0): "Contains information from
  Realtime Weather Readings and PSI/PM2.5 datasets accessed from data.gov.sg, made available
  under the terms of the Singapore Open Data Licence version 1.0."
* Blocks: `FreshnessBadge(Status, AsOf)`, `BandChip(Label, Level)` (always renders the label
  and an icon, never colour alone), `StatCard(Label, Value, Unit, Caption)`, `EmptyState`.

## 2. `WeatherRules_Lib` (Foundation, **Library** module)

No entities, no dependencies except OutSystems UI. Every action is **Function = Yes** where
OutSystems allows it, so it can be used in expressions on both client and server.

| Action | Inputs → Output | Rule |
|---|---|---|
| `PsiBand` | `Psi: Integer` → `Band: Text`, `Level: Integer` | ≤50 Good · ≤100 Moderate · ≤200 Unhealthy · ≤300 Very unhealthy · >300 Hazardous · <0 Invalid/0 |
| `Pm25Band` | `Pm25: Integer` → `Band`, `Level` | ≤55 Normal · ≤150 Elevated · ≤250 High · >250 Very high |
| `CompassPoint` | `Degrees: Decimal` → `Text` | `index = Floor((Mod(Degrees,360)+11.25)/22.5) mod 16` over N, NNE … NNW |
| `KnotsToKmh`, `KnotsToMs` | `Decimal` → `Decimal` | ×1.852, ×0.514444, round half-up to 1 dp |
| `Freshness` | `LatestObservedAt`, `Now`, `ThresholdMinutes` → `Status` (Fresh/Stale/NoData) | NullDate → NoData; age ≤ threshold → Fresh |
| `FreshnessThresholdMinutes` | `Endpoint: Text` → `Integer` | 15 for 1-minute feeds, 20 rainfall, 120 psi/pm25 |
| `NearestRegion` | `Lat`, `Lon` → `RegionCode` | haversine to the five PSI label locations |
| `HealthAdvisory` | `PsiLevel` → `Text` | short NEA-style advisory per band |

Client and server variants are needed for some built-ins; where Function = Yes is not
allowed on the client, create `PsiBand` (server) and `PsiBand_Client` (client action) calling
the same expression, and cover both with tests.

Test vectors for every rule are in `tests/vectors/` and are executed by
`Weather_ClientTests` (see §8).

## 3. `DGS_IS` (Foundation, integration service)

### 3.1 Consumed REST API `DataGovSgRealtime`

* Base URL: `https://api-open.data.gov.sg/v2/real-time/api`, **overridden per environment**
  by `OnBeforeRequest` from site property `DGS_BaseUrl` (empty = default). This is how the BDD
  suite points at WireMock in Dev only.
* Methods (all `GET`, query params `date` and `paginationToken` optional):
  `GetAirTemperature`, `GetRelativeHumidity`, `GetWindSpeed`, `GetWindDirection`,
  `GetRainfall` → structure `StationReadingsResponse`; `GetPsi`, `GetPm25` →
  `RegionReadingsResponse`. Generate the structures from
  `tests/contract/fixtures/air_temperature_latest.json` and `psi_latest.json`.
  The PSI `readings` object has dynamic keys; model each known metric as a named attribute
  (`psi_twenty_four_hourly` etc.) with a `RegionValues` structure (`north`, `south`, `east`,
  `west`, `central`).
* Timeout: 15 s.
* `OnBeforeRequest`:
  * add header `x-api-key` from site property `DGS_ApiKey` when not empty;
  * add header `X-Test-Scenario` from site property `DGS_TestScenario` when not empty (Dev
    only; drives WireMock scenarios);
  * set `URL` from `DGS_BaseUrl` when set.
* `OnAfterResponse`: when `StatusCode <> 200`, rewrite the response to
  `{"code": -<StatusCode>, "errorMsg": "HTTP <StatusCode>", "data": null}` with status 200.
  This turns 429/5xx into data the caller can branch on, instead of an exception that loses
  the status code.
* Logging: Service Center integration logging level **Full** in Dev/Test, **Error** in Prod;
  the API key header is masked by not logging request headers.

### 3.2 Public structures (the only things other modules see)

```
NormStation      { StationId Text(10), Name Text(100), Latitude Decimal(9,5), Longitude Decimal(9,5) }
NormReading      { StationId Text(10), ObservedAt DateTime, Value Decimal(10,2) }
NormRegionRow    { RegionCode Text(10), ObservedAt DateTime, Psi24h, Pm25_24h, Pm25_1h, Pm10_24h,
                   O3_8hMax, No2_1hMax, So2_24h Integer, Co_8hMax Decimal(6,2) }
FetchResult      { IsSuccess Boolean, HttpStatus Integer, ErrorMessage Text, Attempts Integer,
                   NextPaginationToken Text, Stations List<NormStation>, Readings List<NormReading>,
                   RegionRows List<NormRegionRow>, DurationMs Integer }
```

### 3.3 Public server actions

* `FetchStationEndpoint(Endpoint: Text, Date: Date, PaginationToken: Text) → FetchResult`
  1. Call the matching method inside `FetchWithRetry` logic: up to 3 attempts; retry when
     `code` is `-429` or `-5xx`, or on `CommunicationException`; wait 1 s, 2 s, 4 s between
     attempts using `Wait(Seconds)` (Advanced SQL `WAITFOR DELAY`, acceptable inside a Timer).
  2. If `code <> 0` → `IsSuccess = False`, `HttpStatus = -code` (or 200 for envelope errors),
     `ErrorMessage = errorMsg`.
  3. Normalise exactly as `tests/reference/normalize.py`: station name falls back to ID,
     null values skipped, duplicate `(stationId, timestamp)` skipped, timestamps parsed with
     `ParseSgtTimestamp` (§3.4).
* `FetchRegionEndpoint(Endpoint, Date, PaginationToken) → FetchResult` — pivots
  `readings.<metric>.<region>` into one `NormRegionRow` per region per item.
* `ParseSgtTimestamp(Text) → DateTime` — expects `YYYY-MM-DDTHH:MM:SS+08:00`, strips the
  offset, then `AddHours(…, -SgtOffsetFromServerHours)` to produce server-local time.

## 4. `Weather_CS` (Core)

### 4.1 Entities (all Public, **Expose Read Only = Yes**)

As in `docs/architecture.md` §5. Points to get right:

* `Station.Id` is **Text** (the upstream ID, e.g. `S109`), not auto-number, so upserts are
  natural and URLs are readable.
* `Reading.Id` is Long Integer auto-number; add the **unique index**
  `(StationId, MetricId, ObservedAt)` and the index `(MetricId, ObservedAt)`.
* `LatestReading` composite identity is not supported, so give it a Long Integer Id and a
  unique index `(StationId, MetricId)`.
* `AirQualityReading` unique index `(RegionId, ObservedAt)`.
* Static entities `Metric` (Code, Label, Unit, Decimals, IsStationLevel, Endpoint),
  `Region` (Code, Label, LabelLatitude, LabelLongitude), `SyncEndpoint`, `SyncStatus`.
* Delete rule on `Reading.StationId` = **Protect**; stations are deactivated, never deleted.

### 4.2 Bulk upsert (Advanced SQL)

Calling `CreateOrUpdate` row by row would be ~100 round trips per sync. Instead serialise the
batch with `JSONSerialize` and MERGE it in one statement (SQL Server 2016+ `OPENJSON`):

```sql
/* UpsertReadings  @ReadingsJson (Text), @MetricId (Integer) — Expand Inline = No */
MERGE {Reading} AS t
USING (
  SELECT StationId, ObservedAt, Value
  FROM OPENJSON(@ReadingsJson)
  WITH (StationId NVARCHAR(10) '$.StationId',
        ObservedAt DATETIME     '$.ObservedAt',
        Value      DECIMAL(10,2) '$.Value')
) AS s
ON  t.[StationId] = s.StationId AND t.[MetricId] = @MetricId AND t.[ObservedAt] = s.ObservedAt
WHEN MATCHED AND t.[Value] <> s.Value THEN UPDATE SET t.[Value] = s.Value
WHEN NOT MATCHED THEN
  INSERT ([StationId], [MetricId], [ObservedAt], [Value])
  VALUES (s.StationId, @MetricId, s.ObservedAt, s.Value);
SELECT @@ROWCOUNT;
```

Equivalent statements: `UpsertStations` (updates Name/coordinates/LastSeenOn, inserts new
with `NearestRegion`), `UpsertLatestReadings` (keeps the newer `ObservedAt` only),
`UpsertAirQuality`. `JSONSerialize` must use the ISO date format; confirm in Dev by logging
the first payload.

### 4.3 Server actions (Public)

| Action | Notes |
|---|---|
| `SyncEndpoint(EndpointCode)` | Fetch latest → upsert stations → upsert readings → upsert latest → write `SyncRun`. All in one transaction per endpoint; any exception is caught, logged, recorded as `Failed`, then **`AbortTransaction` only for that endpoint's data** (the `SyncRun` row is written after the abort so failures are always recorded). |
| `SyncAllEndpoints()` | Loops `SyncEndpoint` over the 7 endpoints with `CommitTransaction` between them, so one failing endpoint never blocks the rest. |
| `Backfill(EndpointCode, Date)` | `WeatherAdmin` only. Loops pages while `NextPaginationToken <> ""`, max 200 pages as a guard. Same upserts. |
| `RollupHour(HourStart)` | `INSERT … SELECT MIN/MAX/AVG/SUM/COUNT … GROUP BY StationId, MetricId` from `Reading` for the hour, MERGE into `HourlyAggregate`. |
| `Purge()` | Deletes `Reading` older than `RawRetentionDays` (7) and `HourlyAggregate` older than `AggregateRetentionDays` (400) in batches of 5 000 with `CommitTransaction` per batch to avoid long locks. Deletes `SyncRun` older than 30 days. |
| `GetSnapshot(MetricCode)` | From `LatestReading` join `Station` where active; computes min/avg/max/count and freshness. |
| `GetStationSeries(StationId, MetricCode, From, To, Interval)` | Validates `From < To`; raw ≤ 48 h, hour ≤ 400 days; raw from `Reading`, hour from `HourlyAggregate`. Raises `InvalidRangeException` / `NotFoundException`. |
| `ListStations(MetricCode, RegionCode, Search, StartIndex, MaxRecords)` | Server-side paging and count. |
| `GetAirQualityLatest()`, `GetAirQualityHistory(Region, From, To)` | Adds bands via `WeatherRules_Lib`. |
| `GetHealth()` | Per endpoint: latest `ObservedAt`, last success, last status, consecutive failures, freshness. |

User exceptions: `InvalidInputException`, `InvalidRangeException`, `NotFoundException`.

### 4.4 Timers

| Timer | Schedule | Timeout | Action |
|---|---|---|---|
| `Timer_SyncRealtime` | every 5 minutes | 4 min | `SyncAllEndpoints` |
| `Timer_Rollup` | hourly at :07 | 10 min | `RollupHour` for the previous hour and re-run for the one before (late data) |
| `Timer_Purge` | daily 03:17 | 30 min | `Purge` |

The platform never runs two instances of the same timer at once, so overlapping syncs are
impossible; the unique index protects against a manual "Sync now" running concurrently.

### 4.5 Site properties

| Name | Default | Purpose |
|---|---|---|
| `DGS_ApiKey` (in `DGS_IS`) | empty | data.gov.sg key; set per environment in Service Center, never in the OML |
| `DGS_BaseUrl` (in `DGS_IS`) | empty | Dev-only override to WireMock |
| `DGS_TestScenario` (in `DGS_IS`) | empty | Dev-only WireMock scenario header |
| `SgtOffsetFromServerHours` (in `WeatherRules_Lib`) | 0 | see §0 |
| `RawRetentionDays` | 7 | |
| `AggregateRetentionDays` | 400 | |
| `SyncEnabled` | True | kill switch for the sync timer during incidents |

### 4.6 Roles

`WeatherAdmin` (Admin screen, Sync now, Backfill). Public screens are anonymous: the data is
open and the app has no personal data. All public server actions validate inputs, because in
Reactive apps every server action called from the client is a reachable endpoint.

## 5. `Weather_API` (Core, exposed REST API `v1`)

Implements `outsystems/api/weather-api.openapi.yaml` exactly (method names = `operationId`,
custom URL paths such as `/stations/{stationId}/readings`).

* Authentication: None (open data). Rate abuse is handled by WAF in front of the ALB.
* Each method calls the `Weather_CS` server action and maps to the output structure;
  `DateTime`s are formatted as ISO-8601 with `+08:00` by `FormatSgt`.
* Errors: methods raise user exceptions whose message is `"<status>|<CODE>|<message>"`
  (e.g. `400|INVALID_RANGE|'from' must be before 'to'`). The API's **OnResponse** callback
  detects the platform error body, rewrites it to the `Error` schema, sets the status code, and
  adds a `correlationId` that is also written with `LogMessage`.
* **OnResponse** also adds `Cache-Control: public, max-age=60`.
* Log level: Service Center REST expose logging **Error** in Prod.

## 6. `Weather` (End-user, Reactive Web)

Default screen `Dashboard`. All screens use data actions that call `Weather_CS` server
actions (one round trip each), not aggregates over large tables.

Add a `data-testid` attribute to each element below (Properties → Attributes); the E2E suite
depends on them.

| Screen | `data-testid`s |
|---|---|
| Dashboard | `screen-dashboard`, `metric-switch` (ButtonGroup), `map`, markers with CSS class `station-marker`, `marker-popup`, `stat-min`, `stat-avg`, `stat-max`, `freshness-badge`, `as-of` |
| Stations | `screen-stations`, `search`, `filter-region`, `stations-table` (cells with `data-col="<metric-code>"` and `data-col="region"`), `pagination`, `export-csv` |
| StationDetail (input `StationId`) | `screen-station-detail`, `station-name`, `range-switch` (buttons carry `aria-pressed`), `series-chart`, `show-as-table`, `series-table`, `not-found` |
| AirQuality | `screen-air-quality`, `region-card` ×5, each with `psi-band`, `psi-value` |
| Admin (`WeatherAdmin`) | `screen-admin`, `sync-now`, `backfill-date`, `backfill-run`, `sync-runs-table` |

Behaviour:

* **Dashboard**: `OnReady` starts a 5-minute client refresh (JavaScript `setInterval`
  calling the screen's refresh action; cleared in `OnDestroy`). The metric switcher stores the
  choice in a client variable. Markers show the value as a label and are coloured on a
  sequential scale from the metric's min/max; rainfall uses a separate scale where 0 is
  neutral. A banner appears when `Freshness <> Fresh`.
* **Stations**: search, region and sort are screen input parameters so the URL is
  shareable and reload keeps state (asserted by E2E). Server-side paging via `StartIndex`/
  `MaxRecords`. CSV export runs a server action that builds the file with the `CSVUtil` Forge component
  (or `RecordListToExcel` if .xlsx is acceptable), then `Download`.
* **StationDetail**: ranges 6 h / 24 h / 7 d / 30 d; ≤24 h uses `raw`, longer uses `hour`.
  Line chart plus island-average overlay; "Show as table" renders the same series in a table
  for screen-reader users.
* **AirQuality**: five `region-card`s with `BandChip`, sub-index table and 24 h trend.
* **Admin**: last 50 `SyncRun`s, per-endpoint freshness, Sync now, Backfill a date.

Error handling: a global `OnException` handler shows a friendly message; `NotFoundException`
on StationDetail renders the `not-found` empty state.

## 7. Performance and security checklist

* Aggregates only fetch the attributes used (OutSystems optimises this automatically when
  data is not passed whole into server actions; check in the debugger).
* No server action call inside a `ListItem` or `For Each` in client logic.
* Lists are paged; the series endpoint caps points (raw 48 h ≈ 2 880 points).
* `Weather_CS` entities are read-only to other modules; writes only through its actions.
* HTTPS enforced and HSTS enabled in Factory Configuration; secure cookies.
* AI Mentor Studio (Architecture Dashboard): zero architecture violations, findings either
  fixed or justified in this guide before submission.

## 8. Test application — `SG Weather Insights Tests`

| Module | Content |
|---|---|
| `Weather_ClientTests` (Reactive, BDDFramework Client Side) | Screen `RulesTests`: one data-driven scenario per vector file. Vectors are added as Resources and parsed with `JSONDeserialize`. |
| `Weather_Tests` (Traditional Web, BDDFramework) | Screens `IngestionTests`, `SyncResilienceTests`, `ApiContractTests` implementing `tests/bdd/*.feature`. Setup sets `DGS_BaseUrl`/`DGS_TestScenario` site properties to the stub and generates a `TestRunId`; Teardown deletes rows created by the run and clears the site properties. |

Never deploy this application to Prod: it is listed in `cicd/manifest.json` with
`"IsTestApplication": true`, and the pipeline excludes it from the Prod deployment plan.

## 9. Version control of OutSystems artefacts

OutSystems keeps module history in the platform. To give reviewers a reproducible snapshot,
after each release tag export the application from LifeTime (**Applications → SG Weather
Insights → Download .oap**) and commit it to `outsystems/oap/` with the version in the file
name. Restoring = upload the OAP in LifeTime or Service Center.
