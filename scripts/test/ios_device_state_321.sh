#!/usr/bin/env bash
# Plan 321: full devicectl device-state listing (connection + pairing detail).
set -uo pipefail
cd "$(dirname "$0")/../.."
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
python3 - "$JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties") or {}
    conn = d.get("connectionProperties") or {}
    props = d.get("deviceProperties") or {}
    if hw.get("deviceType") != "iPhone":
        continue
    print(f"{props.get('name','?')} | udid={hw.get('udid')} | pairing={conn.get('pairingState')} | "
          f"tunnel={conn.get('tunnelState')} | transport={conn.get('transportType')} | "
          f"os={props.get('osVersionNumber')} | devmode={props.get('developerModeStatus')}")
PY
