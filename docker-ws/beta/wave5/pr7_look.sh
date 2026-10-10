#!/bin/bash
# Copy the last Maestro debug artifacts + a fresh screenshot of sim A into the evidence folder.
EV=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/pr7_evidence_${1:-fix}
A=8E31AD68-4DBF-4336-AEBF-18148DC9FA07
last=$(ls -td $HOME/.maestro/tests/*/ | head -1)
mkdir -p "$EV/maestro" && cp "$last"/*.png "$EV/maestro/" 2>/dev/null
ls "$EV" "$EV/maestro"
xcrun simctl io $A screenshot "$EV/now.png" 2>&1 | tail -1
xcrun simctl listapps $A 2>/dev/null | grep -A3 'com.mknoon.app' | head -5
