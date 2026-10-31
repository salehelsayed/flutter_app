#!/bin/bash
# Delete harness failure-capture screenshots and UI dumps under an evidence dir.
# They can catch the physical Pixel with the notification shade or Home showing other apps' content.
#   bash docker-ws/scrub_failure_captures.sh <evidence-dir>
D="${1:?evidence dir}"
find "$D" \( -name 'failure-*.png' -o -name 'failure-*-ui.xml' \) -print -delete | wc -l | sed 's/^/scrubbed /'
