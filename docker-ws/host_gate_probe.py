#!/usr/bin/env python3
# Read-only: print the host memory gate result and any native-lease waiters.
import json, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts')); sys.path.insert(0, str(root / 'docker-ws'))
import run_sims_safe, device_campaign_preflight as d
print('host_gate', json.dumps(run_sims_safe.host_gate(), default=str)[:600])
print('native_wanted', json.dumps(d.native_wanted(d.lease_directory(None)), default=str)[:600])
