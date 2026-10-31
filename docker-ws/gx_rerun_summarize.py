#!/usr/bin/env python3
"""GX-002 rerun: redacted fact extraction from captured FLOW logs (emulator sender logcat, iPhone 13 runner syslog).
Prints only event names, UTC times, key generations, routes, outcomes, roles and member states. Drops ids, peer ids,
keys and message text.   python3 -I docker-ws/gx_rerun_summarize.py <emu_flow.txt> <ios_flow.txt>"""
import collections
import json
import re
import sys

SAFE = {"keyGeneration", "epoch", "generation", "route", "source", "outcome", "reason", "status", "deliveryMode",
        "expectedRecipientCount", "liveFanoutState", "inboxStored", "inboxPending", "topicPeers", "role", "state",
        "memberState", "type", "ok", "count", "replayed", "skipped", "accepted", "joined", "hasMedia", "elapsedMs",
        "error", "code", "result", "changed", "unchanged", "recipientClass", "decision", "recipientCount", "pageSize"}


def flows(path):
    for line in open(path, errors="replace"):
        m = re.search(r"\[FLOW\] (\{.*\})\s*$", line)
        if not m:
            continue
        try:
            yield json.loads(m.group(1))
        except ValueError:
            continue


def safe(d):
    return {k: v for k, v in (d or {}).items() if k in SAFE and not (isinstance(v, str) and len(v) > 40)}


def show(path, lo, hi, pat):
    rows = []
    for e in flows(path):
        ts = e.get("ts", "")[11:23]
        if not (lo <= ts <= hi) or not re.search(pat, e.get("event", "")):
            continue
        rows.append(f"{ts}Z {e['event']} {json.dumps(safe(e.get('details')), sort_keys=True)}")
    return rows


emu, ios = sys.argv[1], sys.argv[2]
print("# Sender (emulator) send of the suspect text")
for r in show(emu, "02:59:20", "02:59:30", r"GROUP_SEND|ENCRYPT|KEYS_DB_LOAD_LATEST_FOUND|SIGN_RESPONSE"):
    print(r)
print("\n# iPhone 13 after accept: incoming handling, inbox drain/replay, decrypt key generations, members, roles")
pat = r"HANDLE_INCOMING|REPLAY|DRAIN_OFFLINE_INBOX_(BEGIN|DONE|GROUP_DONE|REPLAY)|INVITE|ACCEPT|MEMBERS_DB_INSERT|ROLE|PROMOT|ADMIN|EVENT_LOG|KEYS_DB_LOAD_BY_GEN_NOT_FOUND|DECRYPT_RESPONSE|GROUP_KEYS_DB_INSERT|KEY_ROTAT|HISTORY|CATCH"
c = collections.Counter()
last = None
for r in show(ios, "03:02:00", "03:06:00", pat):
    key = r.split(" ", 1)[1]
    c[key] += 1
    if c[key] <= 2:
        print(r)
    elif c[key] == 3:
        print(f"... repeats of: {key[:120]}")
print("\n# iPhone 13 decrypt key-generation lookups 03:02-03:06 (generation -> found/not_found counts)")
gen = collections.Counter()
pending = None
for e in flows(ios):
    ts = e.get("ts", "")[11:23]
    if not ("03:02:00" <= ts <= "03:06:00"):
        continue
    ev, d = e.get("event", ""), e.get("details") or {}
    if ev == "GROUP_KEYS_DB_LOAD_BY_GEN_START":
        pending = d.get("keyGeneration")
    elif ev in ("GROUP_KEYS_DB_LOAD_BY_GEN_FOUND", "GROUP_KEYS_DB_LOAD_BY_GEN_NOT_FOUND") and pending is not None:
        gen[(pending, ev.rsplit("_", 1)[-1] if ev.endswith("FOUND") and "NOT" not in ev else "NOT_FOUND")] += 1
        pending = None
for k, n in sorted(gen.items(), key=str):
    print(f"generation={k[0]} {k[1]} x{n}")
