#!/usr/bin/env bash
set -uo pipefail
pkill -f "graphify update" 2>/dev/null
pkill -f "graphify_full_update" 2>/dev/null
sleep 1
pgrep -fl "graphify" || echo "no graphify processes running"
