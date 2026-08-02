#!/usr/bin/env bash
# Plan 321: Flutter's own device discovery (a third, independent path).
set -uo pipefail
cd "$(dirname "$0")/../.."
flutter devices --device-timeout "${1:-30}" 2>&1 | head -25
