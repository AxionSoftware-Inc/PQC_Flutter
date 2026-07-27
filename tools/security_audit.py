#!/usr/bin/env python3
"""High-confidence secret scan for the current tree and every Git blob."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass


MAX_BLOB_BYTES = 2 * 1024 * 1024


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[bytes]


RULES = (
    Rule('private-key', re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')),
    Rule('aws-access-key', re.compile(rb'(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])')),
    Rule('github-token', re.compile(rb'(?<![A-Za-z0-9_])gh[opusr]_[A-Za-z0-9_]{36,255}')),
    Rule('github-fine-grained-token', re.compile(rb'github_pat_[A-Za-z0-9_]{80,255}')),
    Rule('google-api-key', re.compile(rb'AIza[0-9A-Za-z_-]{35}')),
    Rule('slack-token', re.compile(rb'xox[baprs]-[0-9A-Za-z-]{20,}')),
    Rule(
        'aws-secret-assignment',
        re.compile(
            rb'(?i)(?:aws_secret_access_key|aws_secret_key)\s*[:=]\s*["\'][A-Za-z0-9/+=]{32,}["\']'
        ),
    ),
)


def run(*args: str, input_bytes: bytes | None = None) -> bytes:
    return subprocess.check_output(args, input=input_bytes)


def git_blobs() -> tuple[dict[str, set[str]], list[tuple[str, int]]]:
    object_paths: dict[str, set[str]] = {}
    object_ids: list[str] = []
    for line in run('git', 'rev-list', '--objects', '--all').decode().splitlines():
        object_id, _, path = line.partition(' ')
        object_ids.append(object_id)
        if path:
            object_paths.setdefault(object_id, set()).add(path)

    check_input = ('\n'.join(object_ids) + '\n').encode()
    checked = run(
        'git',
        'cat-file',
        '--batch-check=%(objectname) %(objecttype) %(objectsize)',
        input_bytes=check_input,
    ).decode()
    blobs: list[tuple[str, int]] = []
    for line in checked.splitlines():
        object_id, object_type, size_text = line.split()
        size = int(size_text)
        if object_type == 'blob' and size <= MAX_BLOB_BYTES:
            blobs.append((object_id, size))
    return object_paths, blobs


def read_blob_batch(blobs: list[tuple[str, int]]):
    process = subprocess.Popen(
        ['git', 'cat-file', '--batch'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(('\n'.join(item[0] for item in blobs) + '\n').encode())
    process.stdin.close()
    for expected_id, expected_size in blobs:
        header = process.stdout.readline().decode().strip().split()
        if len(header) != 3 or header[0] != expected_id or header[1] != 'blob':
            raise RuntimeError(f'Unexpected git cat-file response: {header!r}')
        size = int(header[2])
        if size != expected_size:
            raise RuntimeError(f'Git blob size changed for {expected_id}')
        payload = process.stdout.read(size)
        process.stdout.read(1)
        yield expected_id, payload
    if process.wait() != 0:
        raise RuntimeError('git cat-file failed')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--current-only', action='store_true')
    args = parser.parse_args()

    if args.current_only:
        tracked = run('git', 'ls-files', '-z').split(b'\0')
        findings = []
        for raw_path in tracked:
            if not raw_path:
                continue
            path = raw_path.decode()
            try:
                payload = open(path, 'rb').read(MAX_BLOB_BYTES + 1)
            except (FileNotFoundError, IsADirectoryError):
                continue
            if len(payload) > MAX_BLOB_BYTES:
                continue
            for rule in RULES:
                if rule.pattern.search(payload):
                    findings.append((rule.name, path, 'working-tree'))
    else:
        object_paths, blobs = git_blobs()
        findings = []
        for object_id, payload in read_blob_batch(blobs):
            for rule in RULES:
                if rule.pattern.search(payload):
                    paths = sorted(object_paths.get(object_id) or {'<unknown-path>'})
                    for path in paths:
                        findings.append((rule.name, path, object_id[:12]))

    if findings:
        print('Potential committed secrets detected:', file=sys.stderr)
        for rule, path, revision in sorted(set(findings)):
            print(f'  {rule}: {path} ({revision})', file=sys.stderr)
        return 1
    print('Secret scan passed: no high-confidence credentials found.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
