#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_ASSET_MIRRORS = {
    ROOT / "apps/phone_flutter/assets/mock/dashboard_today.json": (
        ROOT / "fixtures/snapshots/dashboard_today.json"
    )
}


def main() -> int:
    paths = (
        sorted(ROOT.glob("schemas/*.json"))
        + sorted(ROOT.glob("fixtures/**/*.json"))
        + sorted(APP_ASSET_MIRRORS)
    )
    documents = {}

    for path in paths:
        with path.open(encoding="utf-8") as file:
            documents[path] = json.load(file)

    for mirror, source in APP_ASSET_MIRRORS.items():
        if documents[mirror] != documents[source]:
            raise SystemExit(
                f"{mirror.relative_to(ROOT)} does not match {source.relative_to(ROOT)}"
            )

    print(f"validated {len(paths)} json files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
