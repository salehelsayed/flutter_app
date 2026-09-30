#!/bin/bash
# Stop run_round2_rerun.sh and its Maestro children.
. "$(dirname "$0")/beta_env.sh"
pkill -f run_round2_rerun.sh; pkill -f "run_flow.sh"; pkill -f "maestro --device"
sleep 2; pgrep -f run_round2_rerun.sh >/dev/null && echo "still alive" || echo "rerun stopped"
