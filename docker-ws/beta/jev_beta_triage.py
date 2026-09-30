#!/usr/bin/env python3
"""Jev (TypeSafe System One) triage of ONE beta-test failure. Advisory only.

Reuses redaction + API call from scripts/triage_red_run.py (imported, unchanged)
but asks app-bug questions instead of harness-failure questions:
  * which subsystem failed (one noul per subsystem, so two faults can both fire)
  * product bug vs test/harness problem
  * does the excerpt name its own cause
  * which candidate log line is the root-cause line (choice over lines I pre-pick)

Input: an excerpt file built per failure (Maestro failure + device-log window).
Candidate lines: lines in the excerpt starting with 'CANDIDATE <n>: '.
Output: <excerpt>.jev.json  (compared later against my manual triage).

    python3 docker-ws/beta/jev_beta_triage.py <excerpt.txt>
"""
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))
import triage_red_run as base  # noqa: E402

SUBSYSTEMS = {
    "startup_or_node_connectivity": "The app did not start cleanly, or its P2P node never came online / could not reach the relay.",
    "message_delivery": "A 1:1 text message was not sent, not delivered, duplicated, delayed, or shown with a wrong status.",
    "reactions_edit_delete": "A reaction, edit, reply or delete did not reach the other device or rendered wrongly.",
    "media_transfer": "A photo, video, voice note or private media item failed to upload, download, render or expire.",
    "call_signaling": "A voice call's setup failed: invite, ringing, answer, decline, cancel or hang-up did not reach the other side or left a stuck state.",
    "call_media_connectivity": "A voice call connected at the signaling level but the media path (ICE, TURN, WebRTC, audio session) failed or dropped.",
    "groups": "Creating, joining, messaging in, or leaving a group failed.",
    "notifications_push": "A notification or push wake was missing, duplicated, or opened the wrong screen.",
    "ui_rendering": "The app logic worked but the screen showed the wrong thing, stale state, or a layout blocked an action.",
    "test_harness": "The test tool itself failed: a selector did not match, a tap missed, a timeout was too short, or the device/tool misbehaved, while the app behaved correctly.",
}


def questions(candidates):
    asked = {
        name: {
            "type": "noul",
            "instructions": f"Does this beta-test failure excerpt show this problem? {desc}",
            "criteria": {"true": desc, "false": "The excerpt does not show that problem"},
        }
        for name, desc in SUBSYSTEMS.items()
    }
    asked["product_bug"] = {
        "type": "noul",
        "instructions": "Is this failure a genuine defect in the app or relay, rather than a problem with the test tool or test setup?",
        "criteria": {"true": "A genuine app or relay defect", "false": "A test tool or test setup problem"},
    }
    asked["evidence_sufficient"] = {
        "type": "noul",
        "instructions": "Does this excerpt actually name why the step failed, rather than only showing that it failed?",
        "criteria": {"true": "The specific cause is stated in the text",
                     "false": "Only a generic failure or timeout is visible"},
    }
    if candidates:
        asked["root_cause_line"] = {
            "type": "choice",
            "instructions": "Which numbered CANDIDATE line is the earliest line that shows the root cause of this failure?",
            "criteria": {f"line_{n}": text[:280] for n, text in candidates},
        }
    return asked


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[0]); return 2
    path = pathlib.Path(argv[1])
    text = path.read_text(errors="replace")
    candidates = [(m.group(1), m.group(2)) for m in re.finditer(r"^CANDIDATE (\d+): (.*)$", text, re.M)]
    scrubbed, counts = base.redact(base.tail(text, lines=220))
    risk = base.residual_risk(scrubbed)
    if risk:
        print(f"jev: abandoned, credential-shaped text survived redaction: {risk}"); return 0
    key = base.api_key(REPO)
    if not key:
        print("jev: no TYPESAFE_API_KEY"); return 0
    red_cands = [(n, base.redact(t)[0]) for n, t in candidates]
    payload = base.ask({"beta_failure_excerpt": scrubbed}, questions(red_cands), key)
    a = payload["answers"]
    note = {
        "subsystems": sorted(({"name": k, "p": round(a[k]["noul"], 3)} for k in SUBSYSTEMS),
                             key=lambda d: -d["p"]),
        "product_bug": round(a["product_bug"]["noul"], 3),
        "evidence_sufficient": round(a["evidence_sufficient"]["noul"], 3),
        "root_cause_line": a.get("root_cause_line", {}).get("choice"),
        "root_cause_line_confidence": round(a.get("root_cause_line", {}).get("confidence", 0), 3),
        "model": payload.get("model"),
        "usage": payload.get("usage", {}),
        "redacted": counts,
        "advisory": "Not evidence. Compared against manual triage in the report.",
    }
    out = path.with_suffix(path.suffix + ".jev.json")
    out.write_text(json.dumps(note, indent=1) + "\n")
    top = ", ".join(f'{s["name"]} {s["p"]}' for s in note["subsystems"] if s["p"] >= 0.4) or "-"
    print(f'jev: product_bug={note["product_bug"]} evidence={note["evidence_sufficient"]} '
          f'line={note["root_cause_line"]} ({note["root_cause_line_confidence"]}) fired=[{top}] -> {out}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
