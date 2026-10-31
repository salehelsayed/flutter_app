#!/usr/bin/env python3
"""GX-002 self-leave: follow M1/M2 (sender's two GROUP_SEND_MSG_USE_CASE_SUCCESS rows after a UTC time, in order)
through every [FLOW] line of each actor log that mentions their id prefix. Prints alias, actor, ts, event and safe
details only.   python3 -I docker-ws/gx_selfleave_trace.py <evidence-dir> <sender-after HH:MM:SS>"""
import json, os, re, sys
D, AFTER = sys.argv[1], sys.argv[2]
SAFE = {"keyEpoch", "keyGeneration", "deliveryMode", "expectedRecipientCount", "topicPeers", "connectedTopicPeers",
        "inboxStored", "liveFanoutState", "reason", "outcome", "status", "route", "source", "count", "messageCount",
        "joinedAt", "relayTimestamp", "payloadTimestamp", "decryptMs", "deliveryMs", "skipReason", "transport", "ok"}
def flows(p):
    for l in open(p, errors="replace"):
        m = re.search(r"\[FLOW\] (\{.*\})\s*$", l)
        if m:
            try: yield json.loads(m.group(1)), l
            except ValueError: pass
ids = [e["details"]["messageId"][:8] for e, _ in flows(os.path.join(D, "emu_logcat.txt"))
       if e.get("event") == "GROUP_SEND_MSG_USE_CASE_SUCCESS" and e["ts"][11:19] >= AFTER][:2]
names = dict(zip(ids, ["M1", "M2"]))
for actor, f in [("Emu", "emu_logcat.txt"), ("Pixel", "pixel_logcat.txt"), ("iPhone", "ios13_runner_syslog.txt")]:
    hits = {k: 0 for k in ids}
    for e, raw in flows(os.path.join(D, f)):
        for k in ids:
            if k in raw:
                hits[k] += 1
                d = {a: b for a, b in (e.get("details") or {}).items() if a in SAFE}
                print(f"{names[k]} {actor} {e['ts'][11:23]}Z {e['event']} {json.dumps(d, sort_keys=True)}")
    print(f"# {actor} line counts", {names[k]: v for k, v in hits.items()})
