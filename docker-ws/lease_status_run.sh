#!/bin/bash
# Read-only lease status via the repo script.  host-run bash docker-ws/lease_status_run.sh
exec python3 /Volumes/CrucialX9/flutter_app/scripts/lease_status.py "$@"
