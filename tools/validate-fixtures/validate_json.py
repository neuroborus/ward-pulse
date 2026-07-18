#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    paths = sorted(ROOT.glob("schemas/*.json")) + sorted(
        ROOT.glob("fixtures/**/*.json")
    )

    for path in paths:
        with path.open(encoding="utf-8") as file:
            json.load(file)

    print(f"validated {len(paths)} json files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
