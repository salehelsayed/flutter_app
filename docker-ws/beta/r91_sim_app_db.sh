#!/bin/bash
# Read-only: list the app's database files on one simulator.  r91_sim_app_db.sh <udid>
U=$1; C=$(xcrun simctl get_app_container "$U" com.mknoon.app data 2>/dev/null) || { echo "no app"; exit 0; }
echo "container $C"; find "$C" -maxdepth 4 \( -name '*.db' -o -name '*.sqlite' \) -exec ls -la {} \; 2>/dev/null | head
