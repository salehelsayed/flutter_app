#!/bin/bash
# Read-only: print the plan407 audio port probe files (redacted JSON).
D=/Volumes/CrucialX9/flutter_app_plan407_validation/.codex-test-logs/plan407-step1/native-wrapper-checks/20261020T201727Z-device-audio
for f in port-allocation-probe.redacted.json upper-range-port-probe.redacted.json; do echo "== $f"; head -c 2500 "$D/$f"; echo; done
grep -o '"causal_diagnosis"[^}]*' /Volumes/CrucialX9/flutter_app_plan407_validation/.codex-test-logs/plan407-step1/native-validation-summary.json | head -c 1500
