#!/usr/bin/env python3
"""Audit hosted Dart/Flutter lockfile dependencies through the OSV API."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen


PACKAGE_RE = re.compile(r'^  ([A-Za-z0-9_]+):$')
FIELD_RE = re.compile(r'^    (source|version):\s*"?([^"\s]+)"?\s*$')


def locked_packages(path: Path):
    current = None
    records: dict[str, dict[str, str]] = {}
    for line in path.read_text().splitlines():
        package = PACKAGE_RE.match(line)
        if package:
            current = package.group(1)
            records[current] = {}
            continue
        field = FIELD_RE.match(line)
        if current and field:
            records[current][field.group(1)] = field.group(2)
    return sorted(
        (name, fields['version'])
        for name, fields in records.items()
        if fields.get('source') == 'hosted' and fields.get('version')
    )


def main() -> int:
    packages = locked_packages(Path('pubspec.lock'))
    body = json.dumps({
        'queries': [
            {'package': {'ecosystem': 'Pub', 'name': name}, 'version': version}
            for name, version in packages
        ]
    }).encode()
    request = Request(
        'https://api.osv.dev/v1/querybatch',
        data=body,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urlopen(request, timeout=30) as response:
        results = json.loads(response.read())['results']

    findings = []
    for (name, version), result in zip(packages, results, strict=True):
        for vulnerability in result.get('vulns', []):
            findings.append((name, version, vulnerability['id']))
    if findings:
        print('Known vulnerabilities found in Pub dependencies:', file=sys.stderr)
        for name, version, vulnerability_id in findings:
            print(f'  {name} {version}: {vulnerability_id}', file=sys.stderr)
        return 1
    print(f'OSV Pub audit passed for {len(packages)} hosted packages.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
