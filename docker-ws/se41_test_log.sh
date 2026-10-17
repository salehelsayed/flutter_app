#!/bin/bash
# Print the tail of an SE-41 test-variant log on the Mac. Usage: host-run bash docker-ws/se41_test_log.sh <name> [lines]
tail -n "${2:-40}" "/Volumes/CrucialX9/se41_test/${1:?log name}"
