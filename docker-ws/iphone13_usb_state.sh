#!/bin/bash
# Read-only: usbmuxd/lockdown view of the iPhone 13 when CoreDevice reports it unavailable.
U=00008110-00184D622289801E
for k in ProductVersion PasswordProtected ActivationState; do echo "$k=$(timeout 20 ideviceinfo -u $U -k $k 2>&1 | head -1)"; done
echo "pair=$(timeout 20 idevicepair -u $U validate 2>&1 | sed 's/[0-9A-F]\{8\}-.*//' | head -1)"
timeout 20 idevicediagnostics -u $U diagnostics All 2>/dev/null | grep -iE "Uptime|BootTime" | head -3
timeout 15 xcrun devicectl device info details --device $U 2>&1 | grep -iE "error|4016|reason|description" | head -6
