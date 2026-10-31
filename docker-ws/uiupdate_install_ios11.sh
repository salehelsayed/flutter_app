#!/bin/bash
# Install the UI-Update iOS release app on the iPhone 11 ONLY (no uninstall), launch, verify bundleVersion.
#   host-run bash docker-ws/uiupdate_install_ios11.sh
cd /Volumes/CrucialX9/flutter_app-ui-update || exit 1
IPHONE_UDIDS=00008030-001A6D2801BB802E bash docker-ws/install_iphones_keep_identity.sh
