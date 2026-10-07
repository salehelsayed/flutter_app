#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr comment 5 --body-file - <<'BODY'
Device proof for 0ae068a99 (Pixel 6 `21071FDF600CSC`, alone on the Mac, 2026-10-07 11:06-11:18 UTC):

`production-startup-resume-performance`: **PASS**, `oracle.json` = `{"failures":[]}` (proof attempt `sIkn2e`, run `wave3-run-20261007T110557Z`).

- Both closing paths occurred: one outage healed by the node itself, closed as `RELAY_OUTAGE_TIMING {phase: self_healed, recoveryMode: node_self_healed, totalOutageMs: 474}`, and app-driven reconnects closed as `recovered` (`in_place`).
- Every `recovered` event still carries `relayRefreshMs`, `relayWarmMs` and `reserveRpcMs`, so the original benchmark harnesses can read them.
BODY
