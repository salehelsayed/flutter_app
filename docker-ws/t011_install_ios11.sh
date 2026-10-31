#!/bin/bash
# TRANSFER-011: install the wt-t011 iOS release FLOW-log build on the iPhone 11 ONLY (Codex-UI-approved device, Mknoon not present before).
#   host-run bash docker-ws/t011_install_ios11.sh
cd /Volumes/CrucialX9/flutter_app/build/wt-t011 || exit 1
IPHONE_UDIDS=00008030-001A6D2801BB802E bash docker-ws/install_iphones_keep_identity.sh
