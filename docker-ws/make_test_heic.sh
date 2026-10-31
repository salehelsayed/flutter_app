#!/bin/bash
# Convert the synthetic media-bug test JPEG to HEIC with sips (test data only).
#   host-run bash docker-ws/make_test_heic.sh <quality 0-100>
set -uo pipefail
cd "$(dirname "$0")/.."
D=build/kayan-safe/media-bug/testimg
sips -s format heic -s formatOptions "${1:-80}" "$D/large_test.jpg" --out "$D/large_test.heic" >/dev/null && ls -l "$D/large_test.heic"
command -v exiftool >/dev/null && exiftool -overwrite_original -Orientation=6 -n -Make=Apple -Model="iPhone 13" "$D/large_test.heic" >/dev/null && echo exiftool-set
sips -g pixelWidth -g pixelHeight -g orientation "$D/large_test.heic" | tail -3
