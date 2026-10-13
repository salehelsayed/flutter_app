#!/bin/bash
# Moves Xcode's shared ModuleCache aside (reversible). After DerivedData moved behind a symlink,
# old .pcm files name the module by both paths: "module 'Foundation' is defined in both ...".
D=/Volumes/CrucialX9/mac-development/xcode-derived-data
ls -ld "$HOME/Library/Developer/Xcode/DerivedData"
S=$(date +%y%m%d%H%M%S)
[ -d "$D/ModuleCache.noindex" ] && mv "$D/ModuleCache.noindex" "$D/ModuleCache.parked-$S" && echo "parked $D/ModuleCache.parked-$S"
[ -d "$D/SDKStatCaches.noindex" ] && mv "$D/SDKStatCaches.noindex" "$D/SDKStatCaches.parked-$S" && echo "parked SDKStatCaches"
ls "$D" | head -30
