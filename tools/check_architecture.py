#!/usr/bin/env python3
"""Fast, dependency-free checks for the repository's layer boundaries."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def dart_files(relative: str):
    return (ROOT / relative).rglob("*.dart")


def main() -> int:
    violations: list[str] = []

    for path in dart_files("lib/features"):
        if "/presentation/" not in path.as_posix():
            continue
        text = path.read_text(encoding="utf-8")
        if "network/api_client.dart" in text or "package:chat_core/src/core/network" in text:
            violations.append(
                f"presentation imports transport client: {path.relative_to(ROOT)}"
            )

    for path in dart_files("packages/pqc_engine_sdk"):
        text = path.read_text(encoding="utf-8")
        if "package:flutter/" in text:
            violations.append(
                f"pure SDK imports Flutter: {path.relative_to(ROOT)}"
            )

    for path in (ROOT / "services/backend").rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        if "import dart" in text or "package:flutter" in text:
            violations.append(
                f"backend imports client code: {path.relative_to(ROOT)}"
            )

    forbidden_tracked_names = {"db.sqlite3", "debug.sqlite3"}
    for path in ROOT.rglob("*"):
        if path.is_file() and path.name in forbidden_tracked_names:
            violations.append(f"local database artifact present: {path.relative_to(ROOT)}")

    if violations:
        print("Architecture boundary check failed:", file=sys.stderr)
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 1
    print("Architecture boundary check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
