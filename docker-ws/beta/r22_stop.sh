#!/bin/bash
# Ask the running R2-2 load test to finish now (it still collects logs and writes its summary).
. "$(dirname "$0")/beta_env.sh"
C=$(cat "$BETA/r2-2/current.txt"); touch "$C/.stop"; echo "stop requested: $C"
