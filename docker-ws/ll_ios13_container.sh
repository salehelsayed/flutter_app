#!/bin/bash
# iPhone 13 ONLY: list or copy files in com.mknoon.app's own data container (never the Photos library).
#   ll_ios13_container.sh list <subdir>          | ll_ios13_container.sh copy <path-in-container> <local-out>
U=00008110-00184D622289801E
case "$1" in
  list) timeout 120 xcrun devicectl device info files --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app --subdirectory "$2" 2>&1 ;;
  copy) timeout 180 xcrun devicectl device copy from --device "$U" --domain-type appDataContainer --domain-identifier com.mknoon.app --source "$2" --destination "$3" 2>&1 | tail -3 ;;
esac
