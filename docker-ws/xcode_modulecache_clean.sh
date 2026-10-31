#!/bin/bash
# Remove the shared Xcode module cache (owner/Kayan-approved cache cleanup, only while the native-build lease is FREE).
D="$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"
[ -d "$D" ] && { du -sh "$D" | cut -f1; rm -rf "${D:?}"; echo removed; } || echo "no module cache"
