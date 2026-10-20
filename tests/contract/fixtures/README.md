# Fixtures

Trimmed copies of live responses from `api-open.data.gov.sg/v2/real-time/api/*` captured on
2026-10-20 (station lists shortened to keep files reviewable; shapes, keys and units are
unchanged). Two files are synthetic and say so in their name:

* `edge_duplicates_and_nulls.json` — a repeated station in one timestamp and a null value,
  both of which the normaliser must tolerate.
* `error_envelope.json` — HTTP 200 with `code != 0`, which must be treated as a failure.

Refresh with `make fixtures` (runs `tests/contract/capture_fixtures.py`). The nightly
`contract-live` job validates the live API against the same schemas, so a refresh is only
needed when that job reports drift.
