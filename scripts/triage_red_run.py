#!/usr/bin/env python3
"""Advisory triage note for a failed device run. Never a verdict.

This reads the tail of a red run's log, redacts it, asks TypeSafe System One a
fixed set of typed questions, and writes `<log>.triage.json` beside the log. It
returns no pass/fail status, no gate reads it, and its exit code never reports
whether the run under examination failed.

Opt-in. It does nothing unless MKNOON_TRIAGE=1 and an API key are both present,
so no gate acquires a network dependency by existing.

Redaction runs before the request and fails closed: if credential-shaped text
survives the scrub, the note is abandoned and nothing is sent.

    MKNOON_TRIAGE=1 python3 scripts/triage_red_run.py <log-path>
    python3 scripts/triage_red_run.py --dry-run <log-path>   # print, never send

Measured on 12 real red runs from this repo (2026-09-21): 11 of 12 emitted no
wrong answer; it abstained on both logs that carried only a bare exit code and
asked for the verbose build log, which was the correct next capture in each case.
It is wrong sometimes. Read it as a hint, never as evidence.
"""

import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
TAIL_LINES = 150
TAIL_WIDTH = 300
FIRE = 0.4          # a cause is reported at or above this probability
EVIDENCE_FLOOR = 0.5  # below this the log does not name its own cause; abstain

# --------------------------------------------------------------------------
# Redaction. Order matters: credential assignments are scrubbed before the
# generic path and identifier rules, so a secret sitting in a path is caught.
# --------------------------------------------------------------------------

REDACTIONS = [
    ("credential_assignment", re.compile(
        r"(?i)\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH)[A-Z0-9_]*)"
        r"\s*[=:]\s*[^\s\"',)]+"), r"\1=<redacted>"),
    ("bearer", re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._\-]{8,}"), "Bearer <redacted>"),
    ("relay_addresses", re.compile(r"(?i)\bMKNOON_RELAY_ADDRESSES\s*[=:]\s*\S+"),
     "MKNOON_RELAY_ADDRESSES=<redacted>"),
    ("peer_id", re.compile(r"/p2p/[A-Za-z0-9]{16,}"), "/p2p/<peer>"),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"), "<email>"),
    ("ios_udid", re.compile(r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b"), "<ios-udid>"),
    ("uuid", re.compile(
        r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"),
     "<uuid>"),
    ("adb_serial", re.compile(r"(?<= -s )(?!emulator-)[A-Za-z0-9._:-]{6,}"), "<device>"),
    # Android serials also appear in prose and JSON, without an adb -s prefix.
    ("android_serial", re.compile(
        r"\b(?=[A-Z0-9]{10,24}\b)(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]+\b"),
     "<android-serial>"),
    ("home_path", re.compile(r"/Users/[A-Za-z0-9_.-]+"), "/Users/<user>"),
    ("volume_path", re.compile(r"/Volumes/[^/\s]+"), "/Volumes/<volume>"),
    # Native address updates print IPv6 multiaddresses outside the named
    # relay-address assignment. Keep transport/port diagnostics, not the host.
    ("ipv6_multiaddr", re.compile(r"(?<=/ip6/)[0-9A-Fa-f:.]+"), "<ip>"),
    ("ipv4", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "<ip>"),
]

# If any of these survive the scrub the note is abandoned rather than sent.
RESIDUAL_RISK = [
    ("private_key", re.compile(r"BEGIN (?:[A-Z ]+ )?PRIVATE KEY")),
    ("live_credential", re.compile(
        r"(?i)\b(?:api[_-]?key|secret|password|passwd|token|bearer)\b\s*[=:]\s*"
        r"(?!<redacted>)[A-Za-z0-9._\-]{12,}")),
]


def redact(text):
    """Return (scrubbed_text, {rule: hits}). Pure; no I/O."""
    counts = {}
    for name, pattern, replacement in REDACTIONS:
        text, hits = pattern.subn(replacement, text)
        if hits:
            counts[name] = hits
    return text, counts


def residual_risk(text):
    """Names of credential-shaped patterns still present after redaction."""
    return [name for name, pattern in RESIDUAL_RISK if pattern.search(text)]


def tail(text, *, lines=TAIL_LINES, width=TAIL_WIDTH):
    kept = [line[:width] for line in text.splitlines() if "     at " not in line]
    return "\n".join(kept[-lines:])


# --------------------------------------------------------------------------
# Questions. One Noul per cause so stacked faults both surface: real failures
# here routinely have two. A single Choice forces one winner and buries the
# second at ~0.04.
# --------------------------------------------------------------------------

CAUSES = {
    "signing_or_entitlement": (
        "Code signing, provisioning profile, or entitlement problem: a profile does not "
        "cover the bundle id, signing configuration is absent, or iOS refused an install "
        "because the application-identifier entitlement changed."),
    "device_os_automation_gate": (
        "The device OS refused or did not complete automation: UI-test automation mode "
        "timed out, the device was locked or asleep, or an OS permission gate blocked it."),
    "missing_tunnel_or_transport": (
        "The host could not reach a service on the device: a required tunnel or port "
        "forward was absent, or a connection to a device port was refused."),
    "build_artifact_missing": (
        "A required build product was absent or empty: no test bundles, a missing "
        "xctestrun or apk, or an artifact that was never produced."),
    "host_contention": (
        "Another owner already holds the device or its lease, so this run never started."),
    "tool_version_mismatch": (
        "A host command-line tool changed its contract: an unknown or renamed field, "
        "flag, or output format rejected by the newer tool version."),
    "harness_misuse": (
        "The caller invoked the harness wrongly: a bad or missing argument, a schema or "
        "parameter validation error, before any device work happened."),
    "product_failure": (
        "The software under test genuinely failed: a test assertion about application or "
        "server behaviour did not hold."),
}

NEXT_CAPTURE = {
    "verbose_build_log": "Re-run with the build tool's verbose or full log enabled; the "
                         "current output shows only an exit code.",
    "device_system_log": "Capture the device's system log during the run; the failure is "
                         "on the device side.",
    "device_process_list": "List processes or installed apps on the device; the question "
                           "is what is or is not running there.",
    "host_owner_census": "Check which host process or lease already owns the device.",
    "nothing_more_needed": "The cause is already stated in this output, or the run succeeded.",
}


def questions():
    asked = {
        cause: {
            "type": "noul",
            "instructions": f"Does this log show this specific problem? {description}",
            "criteria": {"true": description,
                         "false": "This log does not show that problem"},
        }
        for cause, description in CAUSES.items()
    }
    asked["evidence_sufficient"] = {
        "type": "noul",
        "instructions": ("Does this excerpt actually name why the run failed, rather than "
                         "only showing that something failed?"),
        "criteria": {
            "true": "The specific cause is stated in the text",
            "false": "Only a generic failure or exit code is visible; the cause is not stated",
        },
    }
    asked["next_capture"] = {
        "type": "choice",
        "instructions": ("To identify why this run failed, what should be captured on the "
                         "next attempt?"),
        "criteria": NEXT_CAPTURE,
    }
    return asked


def decide(answers, *, fire=FIRE, floor=EVIDENCE_FLOOR):
    """Pure composition of the model's answers into an advisory verdict."""
    remaining = dict(answers)
    evidence = remaining.pop("evidence_sufficient")["noul"]
    next_capture = remaining.pop("next_capture")
    scored = sorted(((c, a["noul"]) for c, a in remaining.items()), key=lambda kv: -kv[1])
    fired = [{"cause": c, "probability": round(p, 3)} for c, p in scored if p >= fire]
    if evidence < floor:
        verdict = "abstain"
        fired = []
    elif not fired:
        verdict = "clean"
    else:
        verdict = "report"
    return {
        "verdict": verdict,
        "causes": fired,
        "evidence_sufficient": round(evidence, 3),
        "next_capture": next_capture["choice"],
        "next_capture_confidence": round(next_capture["confidence"], 3),
    }


# --------------------------------------------------------------------------


def api_key(repo_root):
    # An explicitly empty TYPESAFE_API_KEY means "no key", not "look elsewhere":
    # falling through to .env there would make callers that blank the variable
    # reach the network anyway.
    if "TYPESAFE_API_KEY" in os.environ:
        return os.environ["TYPESAFE_API_KEY"] or None
    env_file = repo_root / ".env"
    if not env_file.is_file():
        return None
    for raw in env_file.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        if name.strip() == "TYPESAFE_API_KEY":
            return value.strip().strip("'").strip('"')
    return None


def ask(state, asked, key, *, attempts=4):
    body = json.dumps({"state": state, "model": MODEL, "questions": asked}).encode()
    request = urllib.request.Request(
        ENDPOINT, data=body, method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    delay = 1.0
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 529) and attempt < attempts - 1:
                time.sleep(delay)
                delay *= 2
                continue
            raise
    raise RuntimeError("retries exhausted")


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    dry_run = "--dry-run" in argv[1:]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print(f"usage: {argv[0]} [--dry-run] <log-path>", file=sys.stderr)
        return 2

    log_path = pathlib.Path(args[0])
    if not log_path.is_file():
        print(f"triage: no such log: {log_path}", file=sys.stderr)
        return 2

    repo_root = pathlib.Path(__file__).resolve().parents[1]
    if not dry_run and os.environ.get("MKNOON_TRIAGE") != "1":
        print("triage: disabled (set MKNOON_TRIAGE=1 to enable); nothing written")
        return 0

    excerpt = tail(log_path.read_text(errors="replace"))
    scrubbed, counts = redact(excerpt)
    risk = residual_risk(scrubbed)
    if risk:
        print(f"triage: abandoned, credential-shaped text survived redaction: {risk}",
              file=sys.stderr)
        return 0

    if dry_run:
        print(f"--- would send ({len(scrubbed)} chars) ---")
        print(scrubbed)
        print(f"--- redacted: {counts or 'nothing matched'} ---")
        return 0

    key = api_key(repo_root)
    if not key:
        print("triage: no TYPESAFE_API_KEY in environment or .env; nothing written")
        return 0

    try:
        payload = ask({"run_log_tail": scrubbed}, questions(), key)
    except Exception as exc:  # never let triage disturb its caller
        print(f"triage: request failed ({type(exc).__name__}); nothing written",
              file=sys.stderr)
        return 0

    note = decide(payload["answers"])
    note.update({
        "advisory": "Not evidence. This note gates nothing and can be wrong.",
        "log": str(log_path),
        "model": payload.get("model"),
        "redacted": counts,
        "usage": payload.get("usage", {}),
    })
    out = log_path.with_suffix(log_path.suffix + ".triage.json")
    out.write_text(json.dumps(note, indent=1) + "\n")
    causes = ", ".join(f'{c["cause"]} {c["probability"]}' for c in note["causes"]) or "-"
    print(f'triage: {note["verdict"]} evidence={note["evidence_sufficient"]} '
          f'next={note["next_capture"]} causes=[{causes}] -> {out}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
