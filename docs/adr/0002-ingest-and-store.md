# ADR 0002 — Scheduled ingestion into a local time-series store

**Status:** Accepted

## Context
data.gov.sg real-time endpoints return only the latest reading unless a date is supplied, are
rate-limited, and have occasional outages. Users want trends (24 h, 7 d, 30 d) and responsive
screens.

## Decision
A 5-minute Timer pulls every endpoint once and MERGEs the result into `Reading`, `LatestReading`
and `AirQualityReading`. An hourly Timer builds `HourlyAggregate`; a daily Timer enforces
retention (raw 7 d, hourly 400 d). Screens read only local data.

## Consequences
* Upstream load is constant (7 calls / 5 min) regardless of traffic; rate limits are not a
  scaling concern.
* Up to 5 minutes staleness — acceptable for weather; the UI always shows "as of" time and a
  stale banner past threshold.
* Backfill is an explicit admin action using `?date=` with pagination, re-using the same MERGE,
  so gaps after an outage can be repaired.
* Storage and purge must be operated; monitored via `SyncRun` and `/health`.
