"""Re-capture fixtures from the live API (trims station lists to keep diffs reviewable)."""
import json
import sys
from pathlib import Path

import requests

BASE = "https://api-open.data.gov.sg/v2/real-time/api"
OUT = Path(__file__).parent / "fixtures"
KEEP = {"S109", "S24", "S44", "S60"}

for endpoint, name in [("air-temperature", "air_temperature_latest"),
                       ("relative-humidity", "relative_humidity_latest"),
                       ("psi", "psi_latest")]:
    body = requests.get(f"{BASE}/{endpoint}", timeout=20).json()
    data = body.get("data") or {}
    if "stations" in data:
        data["stations"] = [s for s in data["stations"] if s["id"] in KEEP]
        for r in data["readings"]:
            r["data"] = [d for d in r["data"] if d["stationId"] in KEEP]
    (OUT / f"{name}.json").write_text(json.dumps(body, indent=2, ensure_ascii=False))
    print(f"captured {name}", file=sys.stderr)
