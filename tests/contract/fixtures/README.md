# Fixtures

Trimmed copies of live responses from `api-open.data.gov.sg/v2/real-time/api/*` captured on
2026-10-20 (station lists shortened; shapes, keys and units unchanged).
`error_envelope.json` is synthetic: HTTP 200 with `code != 0`, which must be treated as a
failure. The same files are pasted into the OutSystems BDD tests.

Refresh with `python tests/contract/capture_fixtures.py`. The scheduled CI run validates the
live API against the same schemas, so a refresh is only needed when that job fails.
