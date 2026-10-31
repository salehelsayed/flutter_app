#!/bin/bash
# Read-only: show the flutter_webrtc SPM artifact state in the internal-disk device DerivedData.
D="$HOME/tmp-dd-device/SourcePackages/artifacts"
ls -la "$D" 2>&1 | head; echo ---; ls -laR "$D/flutter_webrtc-1.6.0" 2>&1 | head -20; echo ---; df -h "$HOME" | tail -1
