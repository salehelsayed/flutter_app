#!/bin/bash
# Read-only: emulator serials named in another campaign's device configs.  host-run bash docker-ws/show_campaign_devices.sh <dir>
D="${1:?dir}"; case "$D" in /Volumes/CrucialX9/flutter_app_*) ;; *) echo refused; exit 2;; esac
for f in "$D"/*.json; do echo "$(basename "$f"): $(grep -oE 'emulator-[0-9]+|"(serial|udid|device_id)"' "$f" | sort | uniq -c | tr '\n' ' ')"; done
