#!/bin/bash
# Boot (and wait) or shut down the three disposable simulators used by the iOS catalog journeys.
IDS="6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76 8E31AD68-4DBF-4336-AEBF-18148DC9FA07 DBE8C32E-9F19-4593-860A-B41113791D79"
case "$1" in
  boot) for u in $IDS; do xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 & done; wait
        open -a Simulator >/dev/null 2>&1; xcrun simctl list devices booted | grep -E "$(echo $IDS | tr ' ' '|')" ;;
  shutdown) for u in $IDS; do xcrun simctl shutdown "$u" 2>/dev/null; done; echo "shut down" ;;
esac
