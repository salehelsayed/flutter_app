#!/usr/bin/env python3
"""Extract group catch-up FLOW events from an Android logcat dump, with offsets from APP_BUILD_INFO (process start).
   coldstart_flow_extract.py <logcat.txt>   (prints event names and offsets only; no payload details)"""
import json, re, sys
from datetime import datetime
KEEP = re.compile(r'APP_BUILD_INFO|NODE_START|GROUP_REJOIN_TOPICS_(BEGIN|DONE)|GROUP_DRAIN_OFFLINE_INBOX_TIMING|GROUP_STARTUP|STARTUP.*GROUP|INITIAL|RETRIER_START|GROUP_MSG.*(SAVE|PERSIST|INSERT|STORED)|GROUP_MESSAGE.*(SAVE|PERSIST|INSERT|STORED)|CATCH')
evs = []
for line in open(sys.argv[1], errors='replace'):
    i = line.find('[FLOW] ')
    if i < 0: continue
    try: o = json.loads(line[i+7:].strip())
    except Exception: continue
    evs.append(o)
t0 = next((o for o in evs if o.get('event') == 'APP_BUILD_INFO'), None)
if not t0: print('no APP_BUILD_INFO'); sys.exit(1)
base = datetime.fromisoformat(t0['ts'].replace('Z', '+00:00'))
rejoin = 0
for o in evs:
    e = o.get('event', '')
    if not KEEP.search(e): continue
    off = (datetime.fromisoformat(o['ts'].replace('Z', '+00:00')) - base).total_seconds()
    if off < -1: continue
    if e == 'GROUP_REJOIN_TOPICS_BEGIN': rejoin += 1
    d = o.get('details') or {}
    keep = {k: v for k, v in d.items() if k in ('trigger','reason','source','phase','count','groupCount','saved','pages','durationMs','elapsedMs','outcome','initial','reused','kind')}
    print(f"+{off:7.3f}s {e} {json.dumps(keep) if keep else ''}")
print(f"process_start={t0['ts']} GROUP_REJOIN_TOPICS_BEGIN count={rejoin}")
