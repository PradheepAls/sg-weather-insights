# OutSystems build guide (≈ 2.5 hours)

A step-by-step checklist for building the app in Service Studio (OutSystems 11, Reactive
Web). Names are exact because the tests depend on them. Times are rough budgets.

**What you build:** 3 modules, 5 entities, 1 timer, 3 REST methods, 3 screens, 5 BDD tests.

```
SG Weather Insights            (application)
  DGS_IS        Foundation   calls data.gov.sg, turns JSON into simple lists
  Weather_CS    Core         entities, sync timer, read actions, REST API
  Weather       End-user     3 screens
SG Weather Insights Tests      (separate application, never deployed to Prod)
  Weather_Tests              BDDFramework scenarios
```

---

## 0. Setup — 10 min

1. Install from Forge: **BDDFramework** (server-side). OutSystems Charts and OutSystems UI
   are built in.
2. Create application **SG Weather Insights** with three modules: `DGS_IS` (Service),
   `Weather_CS` (Service), `Weather` (Reactive Web App).
3. Create application **SG Weather Insights Tests** with module `Weather_Tests`
   (Traditional Web, needed by BDDFramework).

## 1. `DGS_IS` — 30 min

### 1.1 Consume REST API `DataGovSg`

* Base URL `https://api-open.data.gov.sg/v2/real-time/api`, timeout 15 s.
* Method `GetStationReadings`: `GET /{Endpoint}`, input `Endpoint` (Text, URL param).
  **Set the response to a single Text attribute (`ResponseText`, received in Body)** instead
  of a generated structure. Parsing then happens in our own action, which the tests can call
  with saved JSON without touching the network.
* Method `GetPsi`: `GET /psi`, response also Text.
* `OnBeforeRequest`: if site property `ApiKey` is not empty, add header `x-api-key`.

### 1.2 Structures

Generate the raw structures from sample JSON (Structures → Add from JSON), pasting
`tests/contract/fixtures/air_temperature_latest.json` → `StationReadingsResponse`, and
`psi_latest.json` → `PsiResponse`. Keep them **private**.

Public structures (what other modules see):

```
StationRow   { StationId Text(10), Name Text(100), Latitude Decimal(9,5), Longitude Decimal(9,5) }
ReadingRow   { StationId Text(10), ObservedAt DateTime, Value Decimal(10,2) }
RegionRow    { Region Text(10), ObservedAt DateTime, Psi24h Integer, Pm25_24h Integer }
FetchResult  { IsSuccess Boolean, ErrorMessage Text, Stations List<StationRow>,
               Readings List<ReadingRow>, Regions List<RegionRow> }
```

### 1.3 Public server actions

| Action | Logic |
|---|---|
| `ParseStationJson(Json) → FetchResult` | `JSONDeserialize` into `StationReadingsResponse`. If `code <> 0` → `IsSuccess = False`, `ErrorMessage = errorMsg`. Else map `stations` → `StationRow` (Name falls back to Id when empty) and every `readings[].data[]` → `ReadingRow`, skipping null values. Timestamps: `TextToDateTime(Substr(timestamp, 0, 19))` (drops `+08:00`; see §5). |
| `ParsePsiJson(Json) → FetchResult` | Same idea: one `RegionRow` per region (north, south, east, west, central) from `psi_twenty_four_hourly` and `pm25_twenty_four_hourly`. |
| `FetchStationReadings(Endpoint) → FetchResult` | Call `GetStationReadings`, pass text to `ParseStationJson`. Exception handler (AllExceptions) → `IsSuccess = False`, `ErrorMessage = ExceptionMessage`. |
| `FetchPsi() → FetchResult` | Same with `GetPsi` / `ParsePsiJson`. |

## 2. `Weather_CS` — 50 min

### 2.1 Entities (Public, Expose Read Only = Yes)

| Entity | Attributes | Index |
|---|---|---|
| `Metric` (static) | Code, Label, Unit, Endpoint. Records: AirTemperature (`air-temperature`, °C) · Humidity (`relative-humidity`, %) · WindSpeed (`wind-speed`, knots) · Rainfall (`rainfall`, mm) | — |
| `Station` | **Id Text(10)** (e.g. `S109`, not auto-number), Name, Latitude, Longitude, LastSeenOn | — |
| `Reading` | Id (Long Integer, auto), StationId → Station, MetricId → Metric, ObservedAt DateTime, Value Decimal(10,2) | **unique** (StationId, MetricId, ObservedAt); (MetricId, ObservedAt) |
| `AirQuality` | Id (Long Integer, auto), Region Text(10), ObservedAt, Psi24h, Pm25_24h | **unique** (Region, ObservedAt) |
| `SyncLog` | Id, RunAt, Source Text(30), IsSuccess, RowsAdded, Message Text(500) | — |

### 2.2 Sync logic (server actions)

* **`SyncMetric(MetricId) → RowsAdded`**
  1. `FetchStationReadings(Metric.Endpoint)`; on failure write `SyncLog` and return.
  2. Upsert each station: `CreateOrUpdateStation` (Id is the upstream ID, so this is a natural
     upsert), set `LastSeenOn`.
  3. **Skip if already stored**: aggregate `Reading` where `MetricId = X` and
     `ObservedAt = first reading's ObservedAt`, Max Records 1. If found → nothing new upstream
     since the last run; log and return. This makes the timer idempotent.
  4. For each reading → `CreateReading`. The unique index is the safety net if two runs ever
     overlap (catch `DatabaseException`, log, continue).
  5. Write `SyncLog` (`Source = Metric.Code`, rows added).
* **`SyncAirQuality()`** — same pattern with `FetchPsi`.
* **`SyncAll()`** — `SyncMetric` for the 4 metrics + `SyncAirQuality`, with `CommitTransaction`
  after each so one failing feed never rolls back the others. Then purge: Advanced SQL
  `DELETE FROM {Reading} WHERE {Reading}.[ObservedAt] < @Cutoff` (now − 7 days), and the same
  for `SyncLog` older than 30 days.
* **Timer `Timer_Sync`** — every 15 minutes, runs `SyncAll`. Also set "Run when published"
  so data appears immediately.

### 2.3 Read actions (Public)

| Action | Returns |
|---|---|
| `PsiBand(Psi) → Band, Level` (Function = Yes) | ≤ 50 Good · ≤ 100 Moderate · ≤ 200 Unhealthy · ≤ 300 Very unhealthy · > 300 Hazardous (NEA 24-h PSI) |
| `GetSnapshot(MetricId)` | Latest `ObservedAt` for the metric (aggregate, sort desc, 1 row), then all readings at that time joined with Station; plus Min/Avg/Max computed in the same action |
| `GetStationSeries(StationId, MetricId, Hours)` | Readings from now − Hours, ascending. `Hours` must be 1–168, else raise user exception `InvalidInput` |
| `GetAirQualityLatest()` | The 5 rows at the latest `ObservedAt`, with `Band`/`Level` from `PsiBand` |

### 2.4 Exposed REST API `WeatherAPI`

Implements `outsystems/api/weather-api.openapi.yaml`:

| Method | URL | Calls |
|---|---|---|
| `GetStations` | `GET /stations?metric=air-temperature` | `GetSnapshot` |
| `GetStationReadings` | `GET /stations/{stationId}/readings?metric=…&hours=24` | `GetStationSeries` |
| `GetAirQuality` | `GET /air-quality` | `GetAirQualityLatest` |

Unknown metric or out-of-range hours → `HTTPRequestHandler.SetStatusCode(400)` and return
empty; unknown station → 404. No authentication (the data is public open data).

### 2.5 Site properties

`ApiKey` in `DGS_IS` (empty by default, set per environment in Service Center — never in code).

## 3. `Weather` UI — 45 min

Default theme. Add a footer: *"Contains information from data.gov.sg made available under the
Singapore Open Data Licence v1.0."* Add each `data-testid` as an attribute (Properties →
Attributes) — the E2E tests rely on them.

| Screen | Content | `data-testid`s |
|---|---|---|
| **Dashboard** (default) | ButtonGroup to pick the metric · three stat cards Min / Avg / Max with unit · "As of HH:mm" · Search input that filters the table on the client (`ListFilter`) · Table of stations (name, value, time), sortable by clicking headers (Table widget `OnSort`) · row click → StationDetail | `screen-dashboard`, `metric-switch`, `stat-min`, `stat-avg`, `stat-max`, `as-of`, `search`, `stations-table` |
| **StationDetail** (inputs `StationId`, `MetricId`) | Station name · metric ButtonGroup · range ButtonGroup 24 h / 3 d / 7 d · LineChart of `GetStationSeries` · empty state if the station doesn't exist | `screen-station-detail`, `station-name`, `range-switch`, `series-chart`, `not-found` |
| **AirQuality** | 5 cards (one per region): PSI value, band **as text** plus a coloured left border by level, PM2.5 24 h | `screen-air-quality`, `region-card`, `psi-band`, `psi-value` |

Colour must never be the only signal: the band is always written out.

## 4. `Weather_Tests` — 15 min

One screen `WeatherTests` with BDDFramework blocks. Paste fixture JSON from
`tests/contract/fixtures/` into Text literals (or module Resources).

| Scenario | Given / When / Then |
|---|---|
| PSI bands follow NEA thresholds | values 50, 51, 100, 101, 301 → Good, Moderate, Moderate, Unhealthy, Hazardous (cases in `tests/vectors/psi_band.json`) |
| Station payload is parsed | `air_temperature_latest.json` → 4 stations, 4 readings, S109 = 27.3 |
| PSI payload is parsed | `psi_latest.json` → 5 regions, west PSI = 114 |
| Error envelope is a failure | `error_envelope.json` → `IsSuccess = False`, message contains "Invalid date format" |
| Sync is idempotent | call `SyncMetric(AirTemperature)` twice → second call adds 0 rows |

## 5. Decisions to be ready to explain

* **Store, don't proxy.** The timer makes 5 upstream calls every 15 minutes regardless of how
  many users there are, so rate limits don't scale with traffic, the screens still work when
  data.gov.sg is down, and the line chart has history (the API only returns the latest
  reading by default).
* **Idempotency** comes from "skip if this timestamp is already stored" plus a unique index.
* **Parsing is separate from calling**, so tests use saved JSON and don't depend on the network.
* **Time zone:** API timestamps are Singapore time; storing them as server-local is correct
  when the server runs in Singapore time (the Terraform sets this). On a UTC server you would
  add 8 hours in the parse step — call this out as an assumption.
* **Trade-offs taken for scope:** no map, no backfill of past days, no retry/backoff (a failed
  feed simply retries on the next run), no hourly rollups (7 days of raw data is small).
