#!/bin/bash
# install_ios.sh with Xcode 27's explicit ObjC module builds turned off.
# Since the 10-06 Flutter artifacts re-link, explicit-module scans fail with
# "module 'UserNotifications' is needed but has not been provided".
export FLUTTER_XCODE_CLANG_ENABLE_EXPLICIT_MODULES=NO
exec bash "$(dirname "$0")/install_ios.sh" "$@"
