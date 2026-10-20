import json
from pathlib import Path

import pytest

ROOT = Path(__file__).parent


def load(rel: str):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


@pytest.fixture
def fixture():
    return lambda name: load(f"contract/fixtures/{name}")


@pytest.fixture
def vectors():
    return lambda name: load(f"vectors/{name}")
