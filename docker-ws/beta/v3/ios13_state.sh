#!/bin/bash
# Read-only: iPhone 13 lock state and recent automation-mode log lines.
U=00008110-00184D622289801E
xcrun devicectl device info lockState --device $U 2>&1 | tail -4
timeout 8 /opt/homebrew/bin/idevicesyslog -u $U 2>/dev/null | grep -m5 -iE 'automationmode|SpringBoard.*(launch|start)|LocalAuthentication' | cut -c1-200
