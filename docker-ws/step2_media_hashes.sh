#!/bin/bash
# List sha256 + size of app-owned media files newer than <minutes> on a debug Mknoon install (run-as), plus pending_uploads.
#   step2_media_hashes.sh <serial> <minutes>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
adb -s "$1" shell "run-as com.mknoon.app sh -c 'cd /data/data/com.mknoon.app/app_flutter && find media pending_uploads -type f -mmin -$2 -exec sha256sum {} \; -exec stat -c \"%s %y %n\" {} \;'" 2>&1
