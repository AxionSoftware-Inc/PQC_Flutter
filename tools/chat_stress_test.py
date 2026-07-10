#!/usr/bin/env python3
import argparse
import base64
import concurrent.futures
import json
import os
import random
import statistics
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid


def b64_random(byte_length):
    return base64.b64encode(os.urandom(byte_length)).decode("ascii")


def request_json(method, url, payload=None, headers=None, timeout=20):
    body = None
    final_headers = {"Content-Type": "application/json"}
    if headers:
        final_headers.update(headers)
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers=final_headers,
        method=method,
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
            elapsed_ms = (time.perf_counter() - started) * 1000
            return {
                "status": response.status,
                "json": json.loads(raw) if raw else None,
                "elapsed_ms": elapsed_ms,
            }
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        elapsed_ms = (time.perf_counter() - started) * 1000
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"detail": raw}
        return {
            "status": error.code,
            "json": parsed,
            "elapsed_ms": elapsed_ms,
        }
    except (urllib.error.URLError, OSError) as error:
        elapsed_ms = (time.perf_counter() - started) * 1000
        return {
            "status": 0,
            "json": {"detail": str(error)},
            "elapsed_ms": elapsed_ms,
        }


def call_with_retry(action, *, attempts=6, base_delay=0.1):
    last_error = None
    for attempt in range(attempts):
        try:
            result = action()
        except Exception as error:
            last_error = error
            if attempt == attempts - 1:
                raise
            time.sleep(base_delay * (2 ** attempt))
            continue

        status = result.get("status", 0)
        if status == 0 or status >= 500:
            last_error = RuntimeError(f"transient failure: {status} {result.get('json')}")
            if attempt == attempts - 1:
                raise last_error
            time.sleep(base_delay * (2 ** attempt))
            continue
        return result

    if last_error is not None:
        raise last_error
    raise RuntimeError("retry loop exited without a result")


def login_user(base_url, run_id, index):
    device_id = f"load-{run_id}-{index}-{uuid.uuid4().hex[:8]}"
    payload = {
        "display_name": f"Load {run_id} User {index:03d}",
        "device_id": device_id,
        "device_name": f"load-device-{index:03d}",
        "platform": "load-test",
        "identity_public_key": b64_random(32),
        "key_algorithm": "x25519",
        "pqc_public_key": b64_random(1184),
        "pqc_algorithm": "ml-kem-768",
        "pqc_signing_public_key": b64_random(1952),
        "pqc_signing_algorithm": "ml-dsa-65",
    }
    response = call_with_retry(
        lambda: request_json("POST", f"{base_url}/auth/login", payload=payload)
    )
    if response["status"] != 200:
        raise RuntimeError(
            f"login failed for user {index}: {response['status']} {response['json']}"
        )
    data = response["json"]
    return {
        "index": index,
        "account_id": data["account_id"],
        "device_id": data["device_id"],
        "token": data["token"],
        "workspace_id": data["active_workspace_id"],
        "login_ms": response["elapsed_ms"],
    }


def auth_headers(session):
    return {
        "Authorization": f"Token {session['token']}",
        "X-Device-Id": session["device_id"],
        "X-Workspace-Id": str(session["workspace_id"]),
    }


def fetch_group_conversation(base_url, session):
    response = call_with_retry(
        lambda: request_json(
            "GET",
            f"{base_url}/conversations",
            headers=auth_headers(session),
        )
    )
    if response["status"] != 200:
        raise RuntimeError(
            f"fetch conversations failed for user {session['index']}: "
            f"{response['status']} {response['json']}"
        )
    conversations = response["json"] or []
    group = next((item for item in conversations if item.get("type") == "group"), None)
    if group is None:
        raise RuntimeError(f"group conversation missing for user {session['index']}")
    return {
        "conversation_id": group["id"],
        "fetch_ms": response["elapsed_ms"],
    }


def create_private_conversation(base_url, session, other_account_id):
    response = call_with_retry(
        lambda: request_json(
            "POST",
            f"{base_url}/private-conversations",
            payload={"other_user_id": other_account_id},
            headers=auth_headers(session),
        )
    )
    if response["status"] != 200:
        raise RuntimeError(
            f"private conversation failed for user {session['index']}: "
            f"{response['status']} {response['json']}"
        )
    return {
        "conversation_id": response["json"]["id"],
        "create_ms": response["elapsed_ms"],
    }


def build_group_ciphertext(index):
    key_id = f"load-group-key-{index:03d}"
    return ":".join(
        [
            "group:v1",
            key_id,
            b64_random(12),
            b64_random(96),
            b64_random(16),
        ]
    )


def build_synthetic_pqc_payload(sender_device_id, target_device_id):
    return ":".join(
        [
            "pqc:v1",
            sender_device_id,
            b64_random(1952),
            target_device_id,
            b64_random(1088),
            b64_random(12),
            b64_random(32),
            b64_random(16),
            b64_random(1088),
            b64_random(12),
            b64_random(32),
            b64_random(16),
            b64_random(12),
            b64_random(64),
            b64_random(16),
            b64_random(3309),
        ]
    )


def send_message(base_url, session, conversation_id, body, message_type="text"):
    payload = {
        "body": body,
        "client_message_id": uuid.uuid4().hex,
        "message_type": message_type,
        "attachment_ids": [],
    }
    response = call_with_retry(
        lambda: request_json(
            "POST",
            f"{base_url}/conversations/{conversation_id}/messages",
            payload=payload,
            headers=auth_headers(session),
            timeout=30,
        )
    )
    if response["status"] != 201:
        raise RuntimeError(
            f"send failed for user {session['index']}: {response['status']} {response['json']}"
        )
    return response["elapsed_ms"]


def percentile(values, pct):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, int(round((pct / 100) * (len(ordered) - 1)))))
    return ordered[index]


def summarize_latencies(name, values):
    return {
        "stage": name,
        "count": len(values),
        "avg_ms": round(statistics.mean(values), 2) if values else 0.0,
        "p50_ms": round(percentile(values, 50), 2),
        "p95_ms": round(percentile(values, 95), 2),
        "max_ms": round(max(values), 2) if values else 0.0,
    }


def find_server_pid(explicit_pid):
    if explicit_pid:
        return explicit_pid
    command = ["ps", "-axo", "pid=,command="]
    output = subprocess.check_output(command, text=True)
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        pid_text, command_text = parts
        if "manage.py runserver" in command_text or "gunicorn" in command_text:
            return int(pid_text)
    return None


def read_rss_kb(pid):
    if pid is None:
        return None
    try:
        output = subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True)
    except subprocess.CalledProcessError:
        return None
    output = output.strip()
    if not output:
        return None
    try:
        return int(output)
    except ValueError:
        return None


class MemorySampler:
    def __init__(self, pid, interval_seconds):
        self._pid = pid
        self._interval_seconds = interval_seconds
        self._samples = []
        self._stop = threading.Event()
        self._thread = None

    @property
    def samples(self):
        return list(self._samples)

    def start(self):
        if self._pid is None:
            return
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)

    def _run(self):
        while not self._stop.is_set():
            rss_kb = read_rss_kb(self._pid)
            if rss_kb is not None:
                self._samples.append((time.time(), rss_kb))
            self._stop.wait(self._interval_seconds)


def run_stage(items, worker_count, task):
    latencies = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = [executor.submit(task, item) for item in items]
        for future in concurrent.futures.as_completed(futures):
            latencies.append(future.result())
    return latencies


def main():
    parser = argparse.ArgumentParser(description="PQC chat backend stress test.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/api")
    parser.add_argument("--users", type=int, default=200)
    parser.add_argument("--workers", type=int, default=50)
    parser.add_argument("--server-pid", type=int)
    parser.add_argument("--memory-sample-interval", type=float, default=0.2)
    args = parser.parse_args()

    run_id = time.strftime("%Y%m%d%H%M%S")
    server_pid = find_server_pid(args.server_pid)
    memory_before_kb = read_rss_kb(server_pid)
    sampler = MemorySampler(server_pid, args.memory_sample_interval)
    sampler.start()
    started_at = time.perf_counter()

    sessions = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [
            executor.submit(login_user, args.base_url, run_id, index)
            for index in range(args.users)
        ]
        for future in concurrent.futures.as_completed(futures):
            sessions.append(future.result())
    sessions.sort(key=lambda item: item["index"])
    login_latencies = [item["login_ms"] for item in sessions]

    group_fetch_latencies = []
    for session in sessions:
        group_info = fetch_group_conversation(args.base_url, session)
        session["group_conversation_id"] = group_info["conversation_id"]
        group_fetch_latencies.append(group_info["fetch_ms"])

    group_send_latencies = run_stage(
        sessions,
        args.workers,
        lambda session: send_message(
            args.base_url,
            session,
            session["group_conversation_id"],
            build_group_ciphertext(session["index"]),
        ),
    )

    private_pairs = []
    for index in range(0, len(sessions) - 1, 2):
        private_pairs.append((sessions[index], sessions[index + 1]))

    private_create_latencies = []
    for left, right in private_pairs:
        created = create_private_conversation(args.base_url, left, right["account_id"])
        left["private_conversation_id"] = created["conversation_id"]
        right["private_conversation_id"] = created["conversation_id"]
        private_create_latencies.append(created["create_ms"])

    private_send_targets = []
    for left, right in private_pairs:
        private_send_targets.append((left, right))
        private_send_targets.append((right, left))

    random.shuffle(private_send_targets)
    private_send_latencies = run_stage(
        private_send_targets,
        args.workers,
        lambda pair: send_message(
            args.base_url,
            pair[0],
            pair[0]["private_conversation_id"],
            build_synthetic_pqc_payload(pair[0]["device_id"], pair[1]["device_id"]),
        ),
    )

    duration_seconds = time.perf_counter() - started_at
    sampler.stop()
    memory_after_kb = read_rss_kb(server_pid)
    memory_samples = sampler.samples
    peak_memory_kb = max((sample[1] for sample in memory_samples), default=memory_before_kb or 0)

    report = {
        "base_url": args.base_url,
        "run_id": run_id,
        "users": args.users,
        "workers": args.workers,
        "duration_seconds": round(duration_seconds, 2),
        "server_pid": server_pid,
        "memory": {
            "before_mb": round((memory_before_kb or 0) / 1024, 2),
            "peak_mb": round((peak_memory_kb or 0) / 1024, 2),
            "after_mb": round((memory_after_kb or 0) / 1024, 2),
            "sample_count": len(memory_samples),
        },
        "stages": [
            summarize_latencies("login", login_latencies),
            summarize_latencies("fetch_group_conversation", group_fetch_latencies),
            summarize_latencies("group_send", group_send_latencies),
            summarize_latencies("private_conversation_create", private_create_latencies),
            summarize_latencies("private_send", private_send_latencies),
        ],
        "message_shapes": {
            "group_payload_chars": len(build_group_ciphertext(0)),
            "synthetic_private_pqc_payload_chars": len(
                build_synthetic_pqc_payload("sender-device", "target-device")
            ),
        },
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
