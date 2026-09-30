#!/usr/bin/env python3
"""Per-case call timings for an R2-9 validation run (run_r31_validate.sh).

Usage: r31_report.py <run dir>
Reads timeline.txt (case markers, and per case the "calling now" line with the Mac epoch and the emulator clock
offset), android_logcat_live.txt (emulator clock) and ios_log_validate.txt (FLOW ts, UTC). Every time is printed in
seconds after the iPhone sent the invite. Works with the Mac's /usr/bin/python3 (3.9) and in any time zone: the Mac's
UTC offset is derived from the timeline, and the emulator uses the Mac's time zone.
"""
import calendar
import json
import os
import re
import sys

run = sys.argv[1]
m = re.search(r"run-(\d{4})(\d\d)(\d\d)-", os.path.basename(run.rstrip("/")))
YEAR, MON, DAY = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else (2026, 1, 1)


def utc_epoch(ts):  # "2026-09-29T07:18:05.871904Z"
    d, t = ts.rstrip("Z").split("T")
    y, mo, da = map(int, d.split("-"))
    hh, mi, ss = t.split(":")
    return calendar.timegm((y, mo, da, int(hh), int(mi), 0)) + float(ss)


def hms_epoch(hms, tzoff, day=None):  # local HH:MM:SS(.fff) on the run day -> epoch
    hh, mi, ss = hms.split(":")
    mo, da = day if day else (MON, DAY)
    return calendar.timegm((YEAR, mo, da, int(hh), int(mi), 0)) + float(ss) - tzoff


# timeline
cases, order = {}, []
tl = [l.rstrip("\n") for l in open(os.path.join(run, "timeline.txt"), encoding="utf-8", errors="replace")]
tzoff = None
for l in tl:
    c = re.match(r"\[(\d\d:\d\d:\d\d)\] (\S+) calling now; mac_epoch=(\d+) offset=([+-][\d.]+) rt=([\d.]+) emu=\S+ \S+; (.*)$", l)
    if c:
        hh, mi, ss = map(int, c.group(1).split(":"))
        loc = calendar.timegm((YEAR, MON, DAY, hh, mi, ss))
        tzoff = round((loc - int(c.group(3))) / 900.0) * 900
        break
if tzoff is None:
    print("no 'calling now' lines in the timeline")
    sys.exit(0)
for l in tl:
    s = re.match(r"\[(\d\d:\d\d:\d\d)\] === (\S+) (.*)$", l)
    if s:
        name = s.group(2)
        cases[name] = {"name": name, "title": s.group(3), "start": hms_epoch(s.group(1), tzoff), "lines": []}
        order.append(name)
        continue
    c = re.match(r"\[(\d\d:\d\d:\d\d)\] (\S+) calling now; mac_epoch=(\d+) offset=([+-][\d.]+) rt=([\d.]+) emu=\S+ \S+; (.*)$", l)
    if c and c.group(2) in cases:
        k = cases[c.group(2)]
        k.update(call=int(c.group(3)), offset=float(c.group(4)), rt=float(c.group(5)), state=c.group(6))
    x = re.match(r"\[\d\d:\d\d:\d\d\] (\S+) (.*)$", l)
    if x and x.group(1) in cases:
        cases[x.group(1)]["lines"].append(x.group(2))
for i, n in enumerate(order):
    cases[n]["end"] = cases[order[i + 1]]["start"] if i + 1 < len(order) else cases[n]["start"] + 900

# iPhone FLOW events
flow = re.compile(r"\[FLOW\] (\{.*\})\s*$")
ios = []
p = os.path.join(run, "ios_log_validate.txt")
if os.path.exists(p):
    for l in open(p, encoding="utf-8", errors="replace"):
        f = flow.search(l)
        if not f:
            continue
        try:
            ev = json.loads(f.group(1))
            ios.append((utc_epoch(ev["ts"]), ev.get("event"), ev.get("details") or {}))
        except (ValueError, KeyError):
            continue
ios.sort(key=lambda e: e[0])

# Android logcat (emulator clock, Mac time zone)
PAT = [
    ("start_proc", re.compile(r"Start proc (\d+):com\.mknoon\.app/\S+ for (\S+ \{?[^ }]*)")),
    ("wake_parse", re.compile(r"CALL_ANDROID_WAKE_PARSE")),
    ("start_applied", re.compile(r"CALL_ANDROID_ADMISSION event=start_applied")),
    ("fgs", re.compile(r"Background started FGS: Allowed.*MknoonCallForegroundService")),
    ("worker", re.compile(r"Starting work for com\.mknoon\.app\.call\.HeadlessCallAdmissionWorker")),
    ("dart_vm", re.compile(r"The Dart VM service is listening")),
    ("dart_entry", re.compile(r'"event":"CALL_HEADLESS_ADMISSION_ENTRY","details":\{"phase":"begin"')),
    ("node", re.compile(r"GoLog: \[NODE\] Announcing")),
    ("presented", re.compile(r"MKNOON_CALL_PRESENTATION_DIAG result=PRESENTED")),
    ("adm_timeout", re.compile(r"CALL_ANDROID_ADMISSION event=timeout_applied")),
    ("answer", re.compile(r"CALL_ANDROID_ANSWER")),
    ("and_connected", re.compile(r'"event":"CALL_STATE_TRANSITION","details":\{[^}]*"state":"connected"')),
    ("and_ended", re.compile(r'"event":"CALL_STATE_TRANSITION","details":\{[^}]*"state":"ended"')),
]
STEP = re.compile(r'"event":"CALL_HEADLESS_ADMISSION_STEP","details":\{"step":"([a-z_]+)","phase":"(end|error)","elapsedMs":(\d+)')
LC = re.compile(r"^(\d\d)-(\d\d) (\d\d:\d\d:\d\d\.\d+) ")
andr = []
p = os.path.join(run, "android_logcat_live.txt")
if os.path.exists(p):
    for l in open(p, encoding="utf-8", errors="replace"):
        t = LC.match(l)
        if not t:
            continue
        hit = None
        for k, rx in PAT:
            r = rx.search(l)
            if r:
                hit = (k, r)
                break
        s = STEP.search(l) if not hit else None
        if not hit and not s:
            continue
        e = hms_epoch(t.group(3), tzoff, (int(t.group(1)), int(t.group(2))))
        if hit:
            k, r = hit
            extra = ""
            if k == "start_proc":
                extra = "pid %s %s" % (r.group(1), r.group(2))
            if k in ("and_connected", "and_ended"):
                d = re.search(r'"trigger":"([^"]*)".*?"state":"([a-z]+)"(?:,"endReason":"([^"]*)")?', l)
                extra = "%s/%s" % (d.group(1), d.group(3)) if d else ""
            andr.append((e, k, extra))
        else:
            andr.append((e, "step", "%s:%s=%s" % (s.group(1), s.group(2), s.group(3))))


def fmt(v):
    return "-" if v is None else "%+.1f" % v


rows = []
for n in order:
    k = cases[n]
    if "call" not in k:
        print("%s: no call (%s)" % (n, "; ".join(k["lines"][-3:])))
        continue
    lo, hi = k["call"] - 3, k["end"]
    inv = [e for e in ios if e[1] == "CALL_CONTROL_SIGNAL_SEND_RESULT" and e[2].get("type") == "invite" and lo <= e[0] <= hi]
    if not inv:
        print("%s: no iPhone invite between the call and the next case" % n)
        continue
    t0 = inv[0][0]
    nxt = [e[0] for e in ios if e[1] == "CALL_CONTROL_SIGNAL_SEND_RESULT" and e[2].get("type") == "invite" and e[0] > t0]
    ihi = min([hi] + nxt[:1])
    wake = None
    for e in ios:
        if e[1] == "CALL_SIGNALING_LEG_RESULT" and e[2].get("operation") == "mailbox_store" and t0 - 10 <= e[0] <= t0 + 10:
            wake = e[2].get("wake")
    st = {}
    for e in ios:
        if e[1] == "CALL_STATE_TRANSITION" and t0 - 2 <= e[0] <= ihi:
            s = e[2].get("state")
            if s in ("ringing", "connected", "ended") and s not in st:
                st[s] = (e[0] - t0, "%s/%s" % (e[2].get("trigger"), e[2].get("endReason")))
    off = k["offset"]
    ev, steps = {}, []
    for e, kind, extra in andr:
        me = e - off  # emulator epoch -> Mac epoch
        if not (t0 - 2 <= me <= hi):
            continue
        if kind == "step":
            steps.append(extra)
        elif kind not in ev:
            ev[kind] = (me - t0, extra)
    g = lambda key: ev[key][0] if key in ev else None
    pres, ring = g("presented"), (st["ringing"][0] if "ringing" in st else None)
    print("%s  (%s)" % (n, k["title"]))
    print("  before the call: %s" % k["state"])
    print("  iPhone: invite wake=%s, ringing %s, connected %s, ended %s %s" % (
        wake, fmt(ring), fmt(st["connected"][0] if "connected" in st else None),
        fmt(st["ended"][0] if "ended" in st else None), st["ended"][1] if "ended" in st else ""))
    print("  Pixel: start_proc %s %s | start_applied %s | fgs %s | worker %s | dart_vm %s | dart_entry %s | node %s | "
          "PRESENTED %s | admission timeouts %d | answer %s | connected %s | ended %s %s" % (
              fmt(g("start_proc")), ev["start_proc"][1] if "start_proc" in ev else "", fmt(g("start_applied")),
              fmt(g("fgs")), fmt(g("worker")), fmt(g("dart_vm")), fmt(g("dart_entry")), fmt(g("node")), fmt(pres),
              sum(1 for e, kind, _ in andr if kind == "adm_timeout" and t0 - 2 <= e - off <= hi),
              fmt(g("answer")), fmt(g("and_connected")), fmt(g("and_ended")),
              ev["and_ended"][1] if "and_ended" in ev else ""))
    if steps:
        print("  headless steps (ms): %s" % " ".join(steps[:24]))
    gap = (ring - pres) if (ring is not None and pres is not None) else None
    print("  caller ringing minus Pixel PRESENTED: %s s" % fmt(gap))
    rows.append((n, pres, g("answer"), "connected" in st, g("and_connected") is not None, ring, gap,
                 st["ended"][1] if "ended" in st else ""))
print()
print("case   presented  answer  iPhone-connected  Pixel-connected  iPhone-ringing  ringing-minus-presented  end")
for r in rows:
    print("%-6s %9s %7s %17s %16s %15s %24s  %s" % (r[0], fmt(r[1]), fmt(r[2]), r[3], r[4], fmt(r[5]), fmt(r[6]), r[7]))
