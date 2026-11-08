#!/usr/bin/env bash
# Run on the approved host through hetzner_ssh.py / relay_ssh.py after its lane gap.
# Prepend DEPLOY_HOST=hetzner or DEPLOY_HOST=aws to the helper's stdin payload.
# Upload the approved binary via SFTP to the path below before invoking this script.
# A successful result still requires the external real-client dial; its failure
# requires reinstalling the exact backup reported here and restarting relay-server.
set -euo pipefail
sudo -n python3 -I - "${DEPLOY_HOST:?explicit host label required}" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOST = sys.argv[1]
assert HOST in ("hetzner", "aws"), "invalid host label"
EXPECTED = "b81b1af2a81f2a61a7aa6711743605c100811f2fa9d6b67ec6278962c715e79f"
OLD = "d81f6f5982a9b98f9ea4de4526afcc22f20cb5f922b4d0188e1ce9dea78dd00f"
UPLOADED = "/tmp/relay-server.v1.11.4-b81b1af2-m7d3e8017"
BINARY = "/usr/local/bin/relay-server"
THOUGHT_NAMES = (
    "relay_thoughts_weekly_estimated",
    "relay_thought_posters_weekly_estimated",
    "relay_thought_returning_posters_weekly_estimated",
)
ALLOWED = THOUGHT_NAMES + ("relay_backend_durable", "relay_thoughts_snapshot_healthy")


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def run(*cmd, timeout=30):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=timeout).stdout.strip()


def sha(path):
    with pathlib.Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def metric_name(key):
    return key.split("{", 1)[0]


def state(read_metrics=True):
    fields = run("systemctl", "show", "relay-server", "-p", "ActiveState", "-p", "SubState",
                 "-p", "MainPID", "-p", "NRestarts", "-p", "ExecMainStartTimestamp",
                 "-p", "FragmentPath", "-p", "DropInPaths", "-p", "EnvironmentFiles")
    props = dict(line.split("=", 1) for line in fields.splitlines())
    env_paths = re.findall(r"(\S+) \(ignore_errors=(?:yes|no)\)", props.get("EnvironmentFiles", ""))
    if HOST == "aws":
        env_paths = sorted(set(env_paths + ["/etc/mknoon/relay-server.env", "/etc/mknoon/relay-ipv6.env"]))
    paths = [props["FragmentPath"]] + props.get("DropInPaths", "").split() + env_paths
    configs = {path: sha(path) for path in paths if path}
    metrics = {}
    if read_metrics:
        with urllib.request.urlopen("http://127.0.0.1:2112/metrics", timeout=2) as response:
            text = response.read().decode()
        for line in text.splitlines():
            if not line or line.startswith("#"):
                continue
            key, value = line.rsplit(" ", 1)
            if metric_name(key) in ALLOWED:
                metrics[key] = float(value)
    pid = props["MainPID"]
    return {"utc": utc(), "unit": props, "env_files": env_paths, "configs_sha256": configs,
            "metrics": metrics, "live_sha256": sha(BINARY), "process_sha256": sha("/proc/" + pid + "/exe"),
            "version": run(BINARY, "version")}


def healthy(current, expected, require_metrics=True):
    assert current["unit"]["ActiveState"] == "active", "service inactive"
    assert current["unit"]["SubState"] == "running", "service not running"
    assert current["live_sha256"] == expected, "installed binary mismatch"
    assert current["process_sha256"] == expected, "running binary mismatch"
    if require_metrics:
        assert current["metrics"].get("relay_backend_durable") == 1, "durable Redis metric missing"
        assert current["metrics"].get("relay_thoughts_snapshot_healthy") == 1, "Thoughts snapshot unhealthy"


def wait_ready(expected, started):
    while True:
        try:
            current = state()
        except (urllib.error.URLError, TimeoutError):
            if time.monotonic() - started >= 120:
                raise
            time.sleep(min(2, max(0, 120 - (time.monotonic() - started))))
            continue
        healthy(current, expected)
        return current


record = {"host": HOST, "status": "PREFLIGHT", "candidate_sha256": EXPECTED}
try:
    assert run("uname", "-m") == "x86_64", "unexpected architecture"
    before = state()
    record["before"] = before
    healthy(before, OLD)
    assert before["version"] == "relay-server v1.11.3", "unexpected baseline version"
    assert before["env_files"], "no protected service environment file found"
    if HOST == "aws":
        assert len(before["env_files"]) == 2, "both AWS environment files must be present"
    for name in THOUGHT_NAMES:
        assert any(metric_name(key) == name for key in before["metrics"]), "Thoughts series absent"
    assert pathlib.Path(UPLOADED).stat().st_size == 52988009, "uploaded size mismatch"
    assert sha(UPLOADED) == EXPECTED, "uploaded checksum mismatch"
    run("chmod", "0755", UPLOADED)
    assert run(UPLOADED, "version") == "relay-server v1.11.4", "uploaded version mismatch"
    backup = BINARY + ".pre-1.11.4-" + datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    assert not pathlib.Path(backup).exists(), "backup path already exists"
    run("cp", "-p", BINARY, backup)
    assert sha(backup) == OLD, "backup checksum mismatch"
    record["backup"] = backup
except Exception as error:
    record.update(status="ABORTED_BEFORE_INSTALL", error=str(error))
    print(json.dumps(record, sort_keys=True), flush=True)
    sys.exit(2)

try:
    run("install", "-m0755", UPLOADED, BINARY)
    assert sha(BINARY) == EXPECTED, "installed checksum mismatch"
    record["restart_requested_utc"] = utc()
    run("systemctl", "restart", "relay-server", timeout=120)
    record["restart_completed_utc"] = utc()
    start = time.monotonic()
    record["samples"] = []
    restart_count = None
    for offset in (12, 52, 92):
        time.sleep(max(0, offset - (time.monotonic() - start)))
        current = state(read_metrics=False)
        current["target_seconds"] = offset
        current["elapsed_seconds"] = round(time.monotonic() - start, 3)
        record["samples"].append(current)
        healthy(current, EXPECTED, require_metrics=False)
        assert current["version"] == "relay-server v1.11.4", "wrong live version"
        assert current["unit"]["MainPID"] != before["unit"]["MainPID"], "PID did not change"
        assert current["configs_sha256"] == before["configs_sha256"], "service configuration changed"
        if restart_count is None:
            restart_count = current["unit"]["NRestarts"]
            assert restart_count == "0", "service auto-restarted before first sample"
        assert current["unit"]["NRestarts"] == restart_count, "restart count increased"
    after = wait_ready(EXPECTED, start)
    record["after"] = after
    record["readiness_observed_seconds"] = round(time.monotonic() - start, 3)
    assert after["unit"]["NRestarts"] == restart_count, "restart count increased before readiness"
    assert after["configs_sha256"] == before["configs_sha256"], "service configuration changed"
    for key, value in before["metrics"].items():
        if metric_name(key) in THOUGHT_NAMES:
            assert key in after["metrics"], "retained Thoughts week missing"
            assert after["metrics"][key] >= value, "persisted Thoughts count decreased"
    logs = run("journalctl", "-u", "relay-server", "_PID=" + after["unit"]["MainPID"],
               "--no-pager", "-o", "cat", "--grep=Starting relay-server v|backend=redis", "-n", "30")
    record["banner_verified"] = "Starting relay-server v1.11.4" in logs
    record["redis_durable_log_verified"] = "backend=redis durable=true" in logs
    assert record["banner_verified"], "startup banner missing for current PID"
    assert record["redis_durable_log_verified"], "durable Redis startup summary missing"
    record.update(status="LOCAL_CHECKS_PASS_AWAIT_EXTERNAL_CLIENT", finished_utc=utc())
    print(json.dumps(record, sort_keys=True), flush=True)
except Exception as error:
    record.update(status="FAILED_ROLLBACK_REQUIRED", error=str(error), failure_utc=utc())
    try:
        assert sha(backup) == OLD, "rollback artifact changed"
        run("install", "-m0755", backup, BINARY)
        run("systemctl", "restart", "relay-server", timeout=120)
        rollback_started = time.monotonic()
        restored = wait_ready(OLD, rollback_started)
        record["rollback"] = restored
        healthy(restored, OLD)
        assert restored["configs_sha256"] == before["configs_sha256"], "configuration differs after rollback"
        record["status"] = "FAILED_ROLLED_BACK"
    except Exception as rollback_error:
        record["rollback_error"] = str(rollback_error)
    print(json.dumps(record, sort_keys=True), flush=True)
    sys.exit(1)
PY
