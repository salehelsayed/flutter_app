#!/usr/bin/env python3
"""VC-014 prod: one row per round from the evidence files (dial, ring, APS receipt, relay deltas)."""
import re, sys, os, datetime as dt
D = sys.argv[1]; labels = sys.argv[2:]
def ios_ts(line):  # iPhone syslog is local CET (UTC+1)
    m = re.match(r'Oct (\d\d) (\d\d):(\d\d):(\d\d\.\d+)', line)
    if not m: return None
    day, h, mi, s = int(m[1]), int(m[2]), int(m[3]), float(m[4])
    return dt.datetime(2026,10,day,tzinfo=dt.timezone.utc) + dt.timedelta(hours=h-1, minutes=mi, seconds=s)
for L in labels:
    r = lambda f: open(os.path.join(D, f"{L}_{f}")).read() if os.path.exists(os.path.join(D, f"{L}_{f}")) else ""
    dial = dt.datetime.fromisoformat(re.search(r'dial (\S+)Z', r("dial.txt"))[1]).replace(tzinfo=dt.timezone.utc)
    win = r("ios_syslog_window.txt").splitlines()
    aps = [l for l in win if 'receivedPushWithTopic' in l]
    ring = [l for l in win if 'reportNewIncomingCallWithUUID' in l or 'Received add incoming call' in l]
    idle = re.search(r'idle_min=([\d.]+)', r("backgrounded_at.txt"))
    deltas = re.findall(r'relay delta \{([^}]*)\} \+(\d+)', r("attempt.out") or "")
    sent = sum(int(n) for k, n in deltas if 'outcome="sent"' == k.strip())
    disp = sum(int(n) for k, n in deltas if 'wake="dispatched"' in k)
    apns_srv = ""
    if aps:
        m = re.search(r'timestamp (\d{19})', aps[0])
        if m: apns_srv = f"{(dt.datetime.fromtimestamp(int(m[1])/1e9, dt.timezone.utc)-dial).total_seconds():.1f}"
    print(L, f"idle={idle[1] if idle else '?'}", f"rang={'yes' if ring else 'no'}",
          f"dial->ring={(ios_ts(ring[0])-dial).total_seconds():.1f}s" if ring else "dial->ring=-",
          f"aps_pushes_received={len(aps)}", f"dial->apns_server_ts={apns_srv or '-'}s",
          f"relay_voip_sent=+{sent}", f"store_wake_dispatched=+{disp}", f"ios_window_lines={len(win)}")
