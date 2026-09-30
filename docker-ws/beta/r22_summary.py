#!/usr/bin/env python3
"""Summary of one R2-2 load-test run: crashes, resolves seen by the app, quiet-service cadence, errors."""
import json, os, re, sys
from collections import Counter, defaultdict
from datetime import datetime

OUT, SECS, CRASHES, LAUNCHES = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
kind = {}
for line in open(os.path.join(OUT, "services.txt")):
    port, k, _ = line.split()
    kind[int(port)] = k

events, found = Counter(), []
starts, errs, pids = [], Counter(), set()
for line in open(os.path.join(OUT, "ios_log.txt"), errors="replace"):
    m = re.search(r"Runner\[(\d+):", line)
    if m:
        pids.add(m.group(1))
    for pat in ("Unhandled Exception", "LOCAL_MDNS_DISCOVERY_ERROR", "Bad state", "PlatformException"):
        if pat in line:
            errs[pat + ": " + line.split(pat, 1)[1][:90].strip()] += 1
    i = line.find("[FLOW] {")
    if i < 0:
        continue
    try:
        ev = json.loads(line[i + 7:])
    except ValueError:
        continue
    name = ev.get("event", "")
    if not name.startswith("LOCAL_MDNS"):
        continue
    events[name] += 1
    ts = datetime.strptime(ev["ts"][:19], "%Y-%m-%dT%H:%M:%S")
    if name == "LOCAL_MDNS_DISCOVERY_START":
        starts.append(ts)
    if name == "LOCAL_MDNS_PEER_FOUND":
        d = ev.get("details", {})
        found.append((ts, d.get("port"), d.get("host")))

print("run: %s  %d s  crash reports=%d  relaunches=%d  app processes in log=%d" % (os.path.basename(OUT), SECS, CRASHES, LAUNCHES, len(pids)))
print("app LOCAL_MDNS events:", ", ".join("%s=%d" % kv for kv in events.most_common()))
stress = [f for f in found if f[1] in kind]
real = [f for f in found if f[1] not in kind]
by_kind = Counter(kind[f[1]] for f in stress)
print("resolved (PEER_FOUND) fake services: %d (%s), %.1f per min; other peers: %d (%s)" % (
    len(stress), ", ".join("%s=%d" % kv for kv in sorted(by_kind.items())), 60.0 * len(stress) / max(SECS, 1),
    len(real), ", ".join(sorted(set(str(f[2]) for f in real)))[:120]))
per_min = Counter(f[0].strftime("%H:%M") for f in stress)
if per_min:
    mins = sorted(per_min)
    print("per minute (UTC):", " ".join("%s=%d" % (m, per_min[m]) for m in mins))
    lows = [m for m in mins[1:-1] if per_min[m] < 5]
    print("minutes with fewer than 5 resolves (first/last minute excluded):", lows or "none")
q = defaultdict(list)
for ts, port, _ in stress:
    if kind[port] == "quiet":
        q[port].append(ts)
for port in sorted(p for p in kind if kind[p] == "quiet"):
    t = sorted(q.get(port, []))
    gaps = []
    for a, b in zip(t, t[1:]):
        if any(a < s <= b for s in starts):
            continue  # app restarted in between
        gaps.append((b - a).total_seconds())
    print("quiet port %d: %d resolves, max gap %s s" % (port, len(t), int(max(gaps)) if gaps else "n/a"))
print("error-like lines:", sum(errs.values()))
for k, v in errs.most_common(8):
    print("  %4d  %s" % (v, k))
