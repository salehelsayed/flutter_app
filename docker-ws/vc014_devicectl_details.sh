#!/bin/bash
# VC-014 read-only: raw devicectl details error for the iPhone 13 (first lines) + ideviceinfo pairing/lock-ish keys.
timeout 45 xcrun devicectl device info details --device 00008110-00184D622289801E 2>&1 | head -15 | cut -c1-200
ideviceinfo -u 00008110-00184D622289801E -k ProductVersion 2>&1 | head -2
idevicepair -u 00008110-00184D622289801E validate 2>&1 | head -2
