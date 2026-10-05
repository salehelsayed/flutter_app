#!/bin/bash
# Pixel logcat lines matching a regex (last n).
. "$(dirname "$0")/beta_env.sh"
$ADB -s 21071FDF600CSC logcat -d | grep -E "$1" | tail -n "${2:-30}" | cut -c1-500
