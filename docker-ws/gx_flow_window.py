#!/usr/bin/env python3
"""GX-002 self-leave: list [FLOW] events in a UTC window, minus DB-load noise. Ids (first 8 chars, as the app logs them) become hash aliases
(h:xxxxxx) so one message can be followed across actors without printing real ids, keys or text.
   python3 -I docker-ws/gx_flow_window.py <log> <from HH:MM:SS> <to HH:MM:SS> [event-regex] [--raw-keys]"""
import hashlib
import json
import re
import sys

NOISE = re.compile(r"_DB_LOAD|_DB_SAVE_START|DB_QUERY|GROUP_DISCOVERY|_DB_UPSERT_START")
TEXTY = {"text", "content", "body", "plaintext", "preview", "caption", "ciphertext", "key", "keyBytes", "signature",
         "payload", "nonce", "mac"}


def alias(v):
    return "h:" + hashlib.sha1(str(v)[:8].encode()).hexdigest()[:6]


def clean(d):
    out = {}
    for k, v in (d or {}).items():
        if k in TEXTY:
            out[k] = f"<{len(str(v))}ch>"
        elif isinstance(v, str) and (re.search(r"12D3Koo|^[0-9a-f-]{16,}$|^[A-Za-z0-9+/=_-]{24,}$", v) or k.lower().endswith("id")):
            out[k] = alias(v)
        elif isinstance(v, (dict, list)):
            out[k] = clean(v) if isinstance(v, dict) else [alias(x) if isinstance(x, str) and len(x) > 12 else x for x in v][:10]
        else:
            out[k] = v
    return out


def main():
    path, lo, hi = sys.argv[1:4]
    pat = re.compile(sys.argv[4]) if len(sys.argv) > 4 and not sys.argv[4].startswith("--") else None
    for line in open(path, errors="replace"):
        m = re.search(r"\[FLOW\] (\{.*\})\s*$", line)
        if not m:
            continue
        try:
            e = json.loads(m.group(1))
        except ValueError:
            continue
        ev, ts = e.get("event", ""), e.get("ts", "")[11:23]
        if not (lo <= ts[:len(lo)] <= hi) or (pat and not pat.search(ev)) or (not pat and NOISE.search(ev)):
            continue
        print(f"{ts}Z {ev} {json.dumps(clean(e.get('details')), sort_keys=True)[:600]}")


main()
