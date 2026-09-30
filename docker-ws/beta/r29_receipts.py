#!/usr/bin/env python3
"""Per outgoing call on the iPhone: the relay's wake status for the stored invite and how the call ended.

Usage: r29_receipts.py <ios_log_validate.txt> [HH:MM:SS-from HH:MM:SS-to]
Reads the FLOW events in order. For each outgoing invite (CALL_CONTROL_SIGNAL_SEND_RESULT type=invite) it prints the
wake status of the mailbox_store leg just before it, then the call's direct-send result and first terminal state.
"""
import json
import re
import sys

path = sys.argv[1]
lo, hi = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else ("00:00:00", "99:99:99")
flow = re.compile(r'\[FLOW\] (\{.*\})\s*$')
calls = []
last_store = None
cur = None
for line in open(path, encoding="utf-8", errors="replace"):
    m = flow.search(line)
    if not m:
        continue
    try:
        ev = json.loads(m.group(1))
    except ValueError:
        continue
    name, d, ts = ev.get("event"), ev.get("details") or {}, ev.get("ts", "")
    local = line.split()[1][:8] if len(line.split()) > 1 else "?"
    if name == "CALL_SIGNALING_LEG_RESULT" and d.get("operation") == "mailbox_store":
        last_store = d.get("wake")
        if cur is not None and cur["wake"] is None:
            cur["wake"] = last_store
    elif name == "CALL_CONTROL_SIGNAL_SEND_RESULT" and d.get("type") == "invite":
        cur = {"at": local, "ts": ts, "wake": last_store, "direct": None, "states": [], "end": None,
               "directAccepted": d.get("directAccepted"), "mailboxStored": d.get("mailboxStored")}
        last_store = None
        calls.append(cur)
    elif cur is not None and name == "CALL_SIGNALING_LEG_RESULT" and d.get("operation") == "direct_send":
        if cur["direct"] is None:
            cur["direct"] = d.get("result")
    elif cur is not None and name == "CALL_STATE_TRANSITION":
        st = d.get("state")
        if st and (not cur["states"] or cur["states"][-1] != st):
            cur["states"].append(st)
        if st == "ended" and cur["end"] is None:
            cur["end"] = f'{d.get("trigger")}/{d.get("endReason")}'
for c in calls:
    if not (lo <= c["at"] <= hi):
        continue
    reached = "connected" if "connected" in c["states"] else ("ringing" if "ringing" in c["states"] else "never rang")
    print(f'{c["at"]} invite wake={c["wake"]} directAccepted={c["directAccepted"]} direct_send={c["direct"]} '
          f'-> {reached}, end={c["end"]}')
if not calls:
    print("no outgoing invites found")
