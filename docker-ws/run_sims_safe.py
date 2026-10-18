#!/usr/bin/env python3
"""Kayan's disposable-target launcher. Lists need no device or credentials.

Run with major, device-audio, device-media, or notification-recovery.
Targets come from SIMS_* environment values or ignored local_devices.env.
The local file accepts literal shell-style assignments, without evaluation.
KAYAN_TEST_RELAY_FILE must name an ignored file of test multiaddresses.
Audited protocol journeys use disposable emulators; hardware routes stay blocked.
This is a filtered diagnostic run, never an unfiltered major acceptance result.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
MODES = {
    "major": None,
    "device-audio": "android.production_1to1_audio_call",
    "device-media": "android.direct_media_blob_custody",
    "notification-recovery": "notifications.android_recovery_completion",
}
TARGETS = {
    "android-emulator": "SIMS_ANDROID_EMULATOR_DEVICE_ID",
    "android-emulator-second": "SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID",
    "android-emulator-third": "SIMS_ANDROID_EMULATOR_THIRD_DEVICE_ID",
    "android-emulator-fourth": "SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID",
    **{f"ios-simulator-{letter.lower()}": f"SIMS_IOS_SIMULATOR_{letter}_DEVICE_ID"
       for letter in "ABCD"},
}
ALLOWED_INPUTS = {*TARGETS.values(), "SIMS_IOS_SIMULATOR_ID", "KAYAN_TEST_RELAY_FILE",
                  "PLAN399_FIXTURE_HOST_IP", "PLAN347_FIXTURE_HOST_IP"}
LOG_LIMIT = 8 * 1024 * 1024


def ignored(path):
    path = Path(path).resolve()
    if not path.is_relative_to(REPO) or subprocess.run(
        ["git", "-C", str(REPO), "check-ignore", "-q", "--", str(path)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode:
        raise ValueError("path must be inside an ignored repository directory")
    return path


def inputs():
    values = {}
    local = REPO / "docker-ws/local_devices.env"
    if local.exists():
        ignored(local)
        for line in local.read_text().splitlines():
            match = re.match(r"^\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)=(.*)$", line)
            if match and match[1] in ALLOWED_INPUTS:
                parts = shlex.split(match[2], comments=True)
                if len(parts) > 1:
                    raise ValueError("invalid local target assignment")
                values[match[1]] = parts[0] if parts else ""
    # Presence wins, including explicit empty: never fall back to the file.
    values.update({key: os.environ[key] for key in ALLOWED_INPUTS if key in os.environ})
    return values


def pins(values):
    values = dict(values)
    alias = values.get("SIMS_IOS_SIMULATOR_ID")
    primary = values.get("SIMS_IOS_SIMULATOR_A_DEVICE_ID")
    if alias and primary and alias.upper() != primary.upper():
        raise ValueError("conflicting primary simulator selections")
    if "SIMS_IOS_SIMULATOR_A_DEVICE_ID" not in values and alias is not None:
        values["SIMS_IOS_SIMULATOR_A_DEVICE_ID"] = alias
    result = {}
    for role, name in TARGETS.items():
        value = values.get(name, "").strip()
        if not value:
            continue
        pattern = (r"emulator-[0-9]+" if role.startswith("android") else
                   r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
        if not re.fullmatch(pattern, value):
            raise ValueError("invalid explicit disposable target")
        result[role] = value
    if len(set(v.upper() for v in result.values())) != len(result):
        raise ValueError("target roles must be distinct")
    if not result:
        raise ValueError("an explicit disposable target is required")
    return result


def disposable_manifest(manifest):
    """Rebind only audited protocol journeys; native resolver still owns targets.

    Alice uses the explicit fourth role, preserving Bob/Charlie/Dana's existing
    roles. Two-peer runs therefore need just primary+fourth pins, not four VMs.
    No binary profile, command, assertion, dependency or timeout is rewritten.
    """
    result = json.loads(json.dumps(manifest))
    for row in result["capabilities"]:
        if "android.emulator.rebindable" not in row.get("targetCapabilities", []):
            continue
        row["targetCapabilities"] = [c for c in row["targetCapabilities"]
                                     if c != "android.physical"]
        if "android.emulator" not in row["targetCapabilities"]:
            row["targetCapabilities"].append("android.emulator")
        variants = {
            "android.production_1to1_audio_call": "validateAndroidProductionAudioCallEmulatorArtifact",
            "android.connectivity_restore_media_outbox": "validatePrivateMediaOutboxRestoreEmulatorArtifact",
            "groups.media_send_reliability": "validateGroupMediaReliabilityEmulatorArtifact",
        }
        if row["id"] in variants:
            row["artifactValidator"] = variants[row["id"]]
        if row["id"] == "android.production_1to1_audio_call":
            row["assertions"] = [a.replace("physical_emulator_topology", "emulator_pair_topology")
                                 for a in row["assertions"]]
        for lock in row.get("resources", []):
            kind, _, role = lock["name"].partition(":")
            if role == "android-physical":
                lock["name"] = kind + ":android-emulator-fourth"
    return result


def policy(manifest, mode):
    rows = {c["id"]: c for c in manifest["capabilities"]
            if c.get("active", True) and "major" in c.get("modes", [])}
    if mode != "major":
        needed = set()
        def include(key):
            if key not in needed:
                needed.add(key)
                for dependency in rows[key].get("dependencies", []):
                    include(dependency)
        include(MODES[mode])
        rows = {key: row for key, row in rows.items() if key in needed}
    profiles = {p["id"]: p for p in manifest["buildProfiles"]}
    blocked = {}
    for key, row in rows.items():
        associated = {row["buildProfile"]}
        associated.update(r["name"][6:] for r in row.get("resources", [])
                          if r["name"].startswith("build:"))
        credential_profile = any(
            profiles.get(p, {}).get("compileDefines", {}).get(flag) == "true"
            for p in associated for flag in ("PRODUCTION_FCM", "PRODUCTION_APNS")
        )
        capabilities = row.get("targetCapabilities", [])
        if credential_profile or any(c.startswith("credentials.") for c in capabilities):
            blocked[key] = "credentials"
        elif (any(c in capabilities for c in ("android.physical", "ios.physical"))
              or any(r["name"].split(":")[-1] in ("android-physical", "ios-physical")
                     for r in row.get("resources", []))):
            blocked[key] = "physical_data_preservation"
        elif mode == "major" and key in (MODES["device-audio"], MODES["device-media"]):
            blocked[key] = "local_fixture_mode_required"
        elif "legacy.protected-target-contract" in capabilities:
            blocked[key] = "nested_device_policy"
        elif key == "go.relay.integration":
            # This aggregate includes retained live-production transport smokes.
            blocked[key] = "test_relay_not_bound"
    while True:
        added = {key: "blocked_dependency" for key, row in rows.items()
                 if key not in blocked and any(d in blocked for d in row.get("dependencies", []))}
        if not added:
            break
        blocked.update(added)
    used = set()
    for key, row in rows.items():
        if key not in blocked and row["command"][0] != "@prepare-build":
            used.add(row["buildProfile"])
            used.update(r["name"][6:] for r in row.get("resources", [])
                        if r["name"].startswith("build:"))
    for key, row in rows.items():
        if row["command"][0] == "@prepare-build" and row["buildProfile"] not in used:
            blocked.setdefault(key, "unused_build")
    return rows, blocked


def owned_file(path):
    ignored(path)
    if path.is_symlink() or (path.exists() and (
        not stat.S_ISREG(path.stat().st_mode) or path.stat().st_uid != os.getuid()
    )):
        raise ValueError("refused an unowned or linked output")


def write_json(path, value):
    owned_file(path)
    path.write_text(json.dumps(value, indent=2) + "\n")
    path.chmod(0o600)


def run_child(command, environment, directory):
    # Rotate only our two exact regular log files; never remove a run/build tree.
    log, previous = directory / "launcher.log", directory / "launcher.previous.log"
    for path in (log, previous, directory / "first-failure.log"):
        owned_file(path)
    if log.exists():
        log.replace(previous)
    written = dropped = 0
    with log.open("wb") as output:
        log.chmod(0o600)
        with subprocess.Popen(command, cwd=REPO, env=environment,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as child:
            for data in iter(lambda: child.stdout.read1(64 * 1024), b""):
                keep = data[:max(0, LOG_LIMIT - written)]
                output.write(keep)
                written += len(keep)
                dropped += len(data) - len(keep)
            code = child.wait()
    if code and not (directory / "first-failure.log").exists():
        shutil.copyfile(log, directory / "first-failure.log")
        (directory / "first-failure.log").chmod(0o600)
    return code, dropped


def host_gate():
    def sample():
        memory = subprocess.check_output(["/usr/bin/memory_pressure", "-Q"], text=True, timeout=5)
        vm = subprocess.check_output(["vm_stat"], text=True, timeout=5)
        load = subprocess.check_output(["sysctl", "-n", "vm.loadavg"], text=True, timeout=5)
        free = re.search(r"free percentage:\s*(\d+)%", memory)
        swapouts = re.search(r"^Swapouts:\s*(\d+)", vm, re.M)
        load1 = re.search(r"\d+(?:\.\d+)?", load)
        if None in (free, swapouts, load1):
            raise ValueError("host pressure observation unavailable")
        return {"memory_free_percent": int(free[1]), "swapout_pages": int(swapouts[1]),
                "load_1min": float(load1[0])}
    first = sample()
    time.sleep(15)
    second = sample()
    passed = (first["swapout_pages"] == second["swapout_pages"]
              and second["memory_free_percent"] > 25
              and second["load_1min"] < 40
              and shutil.disk_usage(REPO).free > 20 * 1024**3)
    return {"first": first, "second": second, "passed": passed}


@contextlib.contextmanager
def prepared_devices(selected, environment, directory):
    # Reuse the existing cross-checkout leases and fresh automation/availability
    # observations. A passing setup check is not a passing campaign.
    sys.path.insert(0, str(REPO / "scripts"))
    import device_campaign_preflight as preflight
    import mknoon_checks
    devices = {("ios_simulator" if role == "ios-simulator-a" else role.replace("-", "_")): value
               for role, value in selected.items()}
    try:
        with preflight.device_leases(selected.values()):
            receipt = preflight.run(
                {"kind": "full_adapter", "device_roles": list(devices)},
                REPO, {"devices": devices}, mknoon_checks.launch, environment,
            )
            write_json(directory / "preflight.json", receipt)
            if receipt["status"] != "PASS":
                raise ValueError("device preflight did not pass")
            yield
    except preflight.DeviceLeaseBusy:
        raise ValueError("explicit device lease unavailable") from None


class QuietParser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError("invalid launcher arguments")


def main(arguments=None):
    parser = QuietParser(description=__doc__)
    parser.add_argument("mode", choices=MODES)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--output", default="build/kayan-safe")
    options = parser.parse_args(arguments)
    manifest = disposable_manifest(json.loads(
        (REPO / "tool/sims/critical_features.json").read_text()))
    rows, blocked = policy(manifest, options.mode)
    summary = {
        "scope": "filtered diagnostic; physical and credential routes are blocked",
        "rows": [{"id": key, "status": "BLOCKED" if key in blocked else "SELECTED",
                  **({"blocker": blocked[key]} if key in blocked else {})}
                 for key in rows],
    }
    if options.list:
        print(json.dumps(summary, indent=2))
        return 0
    # A phone-required proof is not silently reinterpreted as an emulator proof.
    if options.mode != "major" and MODES[options.mode] in blocked:
        print("BLOCKED: " + blocked[MODES[options.mode]] + "; no campaign launched")
        return 78
    values = inputs()
    selected = pins(values)
    relay = ignored(values.get("KAYAN_TEST_RELAY_FILE", ""))
    if not relay.is_file() or relay.stat().st_size > 64 * 1024:
        raise ValueError("a bounded ignored test relay file is required")
    addresses = [s.strip() for s in re.split(r"[\n,]+", relay.read_text()) if s.strip()]
    if not addresses or any(not s.startswith("/") or re.search(r"\s", s) for s in addresses):
        raise ValueError("invalid test relay file")
    directory = ignored(REPO / options.output)
    if not directory.is_relative_to(REPO / "build/kayan-safe"):
        raise ValueError("output must remain under the launcher's own directory")
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    for name in ("native-report.json", "checkpoint.json", "manifest.json"):
        owned_file(directory / name)
    write_json(directory / "policy.json", summary)
    write_json(directory / "manifest.json", manifest)
    write_json(directory / "device-config.json", {
        "isolated_test_environment": True, "fixture_reference": "explicit-disposable-test-relay",
        "devices": {("ios_simulator" if role == "ios-simulator-a" else role.replace("-", "_")): value
                    for role, value in selected.items()},
        "android_physical": {"enabled": False}, "ios_physical": {"enabled": False},
    })
    summary["host_gate"] = host_gate()
    if not summary["host_gate"]["passed"]:
        summary["status"] = "BLOCKED"
        write_json(directory / "policy.json", summary)
        print("BLOCKED: host disk, memory, swap or load gate; no campaign launched")
        return 78
    # Start with host tooling only. Do not inherit SSH/provider/signing credentials,
    # alternate manifests, device defaults, or ambient prepared-artifact overrides.
    base_names = ("HOME", "PATH", "USER", "TMPDIR", "LANG", "LC_ALL", "DEVELOPER_DIR",
                  "ANDROID_HOME", "ANDROID_SDK_ROOT", "JAVA_HOME", "FLUTTER_ROOT")
    environment = {k: os.environ[k] for k in base_names if k in os.environ}
    environment.update({TARGETS[role]: value for role, value in selected.items()})
    if "ios-simulator-a" in selected:
        environment["SIMS_IOS_SIMULATOR_ID"] = selected["ios-simulator-a"]
        environment["MKNOON_NATIVE_IOS_SIMULATOR_ID"] = selected["ios-simulator-a"]
    if (directory / "deny-remote").is_symlink():
        raise ValueError("refused a linked remote guard directory")
    deny_remote = ignored(directory / "deny-remote")
    deny_remote.mkdir(exist_ok=True)
    for name in ("ssh", "scp", "sftp", "bash"):
        path = deny_remote / name
        owned_file(path)
        # Existing rows use bash -lc: keep the controlled environment rather
        # than reloading a login profile with different targets or credentials.
        path.write_text('#!/bin/sh\nexec /bin/bash --noprofile --norc "$@"\n'
                        if name == "bash" else "#!/bin/sh\nexit 78\n")
        path.chmod(0o700)
    sdk = Path(os.environ.get("MKNOON_FLUTTER_SDK", str(Path.home() / "development/flutter-3.47.2")))
    tool_path = (str(sdk / "bin") + os.pathsep) if (sdk / "bin").is_dir() else ""
    environment["PATH"] = str(deny_remote) + os.pathsep + tool_path + environment.get("PATH", os.defpath)
    environment.update({
        "MKNOON_RELAY_ADDRESSES": ",".join(addresses),
        "SIMS_MANIFEST": str(directory / "manifest.json"),
        "SIMS_DISPOSABLE_ANDROID_JOURNEYS": "1",
        "MKNOON_PRESERVE_PHYSICAL_APP_DATA": "1",
        "SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON": json.dumps(selected),
        "SIMS_IOS_DISPOSABLE_SIMULATOR_IDS": ",".join(
            value for role, value in selected.items() if role.startswith("ios-")),
        "SIMS_MAX_PARALLEL": "1", "SIMS_HOST_CONCURRENCY": "1",
        "MKNOON_HOST_FLUTTER_WORKERS": "1", "GOMAXPROCS": "2", "GOFLAGS": "-p=2",
        "GOTOOLCHAIN": "go1.27.1",
        "GRADLE_OPTS": "-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.daemon=false",
        "SIMS_REPORT_PATH": str(directory / "native-report.json"),
        "SIMS_CHECKPOINT_PATH": str(directory / "checkpoint.json"),
        "GIT_SSH_COMMAND": str(deny_remote / "ssh"),
    })
    if options.mode in ("device-audio", "device-media"):
        first, second = selected.get("android-emulator-fourth"), selected.get("android-emulator")
        if not first or not second:
            raise ValueError("fixture mode requires two explicit emulator pins")
        host_key = "PLAN399_FIXTURE_HOST_IP" if options.mode == "device-audio" else "PLAN347_FIXTURE_HOST_IP"
        host = values.get(host_key, "")
        import ipaddress
        if not host or not ipaddress.ip_address(host).is_private:
            raise ValueError("an explicit private fixture interface is required")
        environment[host_key] = host
        environment["RELIABILITY_MULTI_DEVICE_IDS"] = first + "," + second
    # There is no shell invocation and no local-only skill launcher/device fallback.
    command = ["dart", "run", "tool/sims/sims.dart", "major", "--continue-on-failure"]
    if options.mode in ("device-audio", "device-media"):
        adapter = ("run_production_audio_call_sims.dart" if options.mode == "device-audio"
                   else "run_direct_media_blob_custody_sims.dart")
        command = ["dart", "run", "integration_test/scripts/" + adapter,
                   "--mode", "major", "--scenario", MODES[options.mode]]
    elif options.mode != "major":
        command.extend(["--only", MODES[options.mode]])
    if options.mode == "major":
        for key in blocked:
            command.extend(["--exclude", key])
    with prepared_devices(selected, environment, directory):
        code, dropped = run_child(command, environment, directory)
    summary.update(child_exit=code, discarded_log_bytes=dropped,
                   status="BLOCKED" if blocked and code == 0 else ("PASS" if code == 0 else "FAIL"))
    write_json(directory / "policy.json", summary)
    if code and not (directory / "first-failure.policy.json").exists():
        write_json(directory / "first-failure.policy.json", summary)
    print(f"{summary['status']}: child exit={code}; policy blocks={len(blocked)}; "
          "details in the ignored output directory")
    return (code if code > 0 else 128 - code) if code else (78 if blocked else 0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        print("BLOCKED: invalid or unavailable local configuration; no identifiers displayed",
              file=sys.stderr)
        raise SystemExit(78)
