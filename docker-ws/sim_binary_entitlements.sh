#!/bin/bash
# Read-only: is a keychain/app-group entitlement embedded in the simulator binary (__entitlements section)?
A="${1:?app}"
for b in "$A/Runner" "$A/Runner.debug.dylib"; do echo "$(basename $b): keychain=$(LC_ALL=C grep -a -c keychain-access-groups "$b") appgroups=$(LC_ALL=C grep -a -c com.apple.security.application-groups "$b")"; done
otool -l "$A/Runner" | grep -A3 -E "__ents_der|__entitlements" | head -8
