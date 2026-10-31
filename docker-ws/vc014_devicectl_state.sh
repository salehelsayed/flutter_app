#!/bin/bash
# VC-014 read-only: devicectl view of the iPhone 13 and one bounded details call.
timeout 40 xcrun devicectl list devices 2>&1 | grep -iE "iphone|state|name" | head -8
timeout 45 xcrun devicectl device info details --device 00008110-00184D622289801E 2>&1 | grep -iE "error|tunnelState|ddiServicesAvailable|developerModeStatus|bootState|transportType|Unable|locked" | head -10
idevice_id -l 2>/dev/null | sed 's/\(.\{6\}\).*/\1.../'
