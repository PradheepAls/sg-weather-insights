# ADR 0003 — Four-layer module structure with a pure rules library

**Status:** Accepted

## Decision
`DGS_IS` (consume + normalise) → `Weather_CS` (data, timers, actions) → `Weather_API` (expose)
and `Weather` (UI). Business rules (PSI/PM2.5 banding, freshness, unit conversion, compass
direction) live in `WeatherRules_Lib`, a Library module with no entities.

## Rationale
* Swapping the upstream (e.g. a v3 API) touches only `DGS_IS`.
* Rules are needed on the client (marker colours, labels) and the server (API responses).
  One library avoids two implementations drifting.
* Rules are pure functions, so they are the cheapest and most valuable thing to unit-test.
  The same test vectors in `tests/vectors/` drive OutSystems BDD tests and the Python
  reference implementation, so expected values are reviewed once.
* Tests live in a separate application so LifeTime never promotes them to Prod.
