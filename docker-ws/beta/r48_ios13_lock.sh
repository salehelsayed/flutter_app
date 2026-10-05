#!/bin/bash
# Read-only: iPhone 13 lock state and boot time, then retry is up to the caller.
U=00008110-00184D622289801E
xcrun devicectl device info lockState --device "$U" 2>&1 | tail -6
xcrun devicectl device info details --device "$U" 2>&1 | grep -iE 'bootedSince|developerModeStatus|ddiServicesAvailable|tunnelState' | head
