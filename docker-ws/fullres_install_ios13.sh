#!/bin/bash
# Install the full-res iOS build from build/wt-fullres on the iPhone 13 ONLY, keeping identity and data (no uninstall).
#   host-run bash docker-ws/astra_c_install_ios13.sh
cd /Volumes/CrucialX9/flutter_app/build/wt-fullres || exit 1
IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
