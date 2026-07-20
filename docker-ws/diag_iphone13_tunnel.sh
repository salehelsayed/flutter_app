#!/bin/bash
# Read-only diagnostic: what on the Mac is touching CoreDevice / the iPhone 13
# tunnel (00008110-00184D622289801E)? Run via host-run from the container.
echo "== devicectl / CoreDevice-related processes"
ps aux | grep -iE 'devicectl|CoreDeviceService|remotepairing|idevicesyslog|instruments' | grep -v grep
echo "== remoted"
ps aux | grep -w 'remoted' | grep -v grep
echo "== Xcode-ish"
ps aux | grep -iE 'Xcode|Console.app' | grep -v grep | head -5
echo "== available libimobiledevice/pymobiledevice tools"
for t in idevicediagnostics ideviceinfo idevicepair idevicesyslog pymobiledevice3 ideviceinstaller ios-deploy; do
  command -v "$t" >/dev/null 2>&1 && echo "have: $t"
done
exit 0
