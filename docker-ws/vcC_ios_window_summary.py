#!/usr/bin/env python3
"""Summarize one VC-014 iPhone call window (redacted): CallKit report count, presentations, state transitions, audio lines.
   python3 -I docker-ws/vcC_ios_window_summary.py <window.txt>"""
import re
import sys

seen = []
for l in open(sys.argv[1], errors="replace"):
    mt = re.search(r"\d\d:\d\d:\d\d\.\d+", l)
    t = mt.group(0) if mt else "?"
    if "Received add incoming call" in l or "CALL_INCOMING_PRESENTATION_ATTEMPT" in l and "Runner" not in l:
        seen.append(f"{t} callkit_add_incoming")
    m = re.search(r'"event":"(CALL_INCOMING_PRESENTATION_RESULT|CALL_STATE_TRANSITION)".*?"details":(\{[^}]*\})', l)
    if m:
        if m.group(1) == "CALL_STATE_TRANSITION":
            tr = re.search(r'"trigger":"(\w+)","state":"(\w+)","endReason":"(\w+)"', m.group(2))
            if tr and tr.group(1) not in ("remoteIce", "iceCandidateHandled"):
                seen.append(f"{t} {tr.group(1)}->{tr.group(2)} end={tr.group(3)}")
        else:
            seen.append(f"{t} presentation {m.group(2)}")
    if "MKNOON_CALLKIT_DIAG" in l and "audio" in l:
        seen.append(f"{t} " + l.split("MKNOON_CALLKIT_DIAG]")[1].strip()[:80])
    if "CALL_INCOMING_SIGNAL_NOT_ACCEPTED" in l:
        seen.append(f"{t} replay_rejected")
out, prev, n = [], None, 0
for s in seen + [None]:
    k = s.split(" ", 1)[1] if s else None
    if k == prev == "replay_rejected":
        n += 1
        continue
    if prev == "replay_rejected" and n > 1:
        out[-1] += f" x{n}"
    if s:
        out.append(s)
    prev, n = k, 1
print("\n".join(out))
print("callkit_add_incoming_count", sum(1 for s in seen if "callkit_add_incoming" in s))
