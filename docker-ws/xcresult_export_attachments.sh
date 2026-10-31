#!/bin/bash
# Read-only: export attachments (screenshots) from an xcresult into a private folder.
#   host-run bash docker-ws/xcresult_export_attachments.sh <xcresult> <out-dir>
mkdir -p "$2" && chmod 700 "$2"
/usr/bin/xcrun xcresulttool export attachments --path "$1" --output-path "$2" 2>&1 | tail -5
ls -la "$2" | head -30
