#!/bin/bash
# Read-only: does the iPhone 13 have a SIM / cellular data? (plan 406 remaining checks)
/opt/homebrew/bin/ideviceinfo -u 00008110-00184D622289801E 2>/dev/null | grep -iE '^(SIMStatus|SIMTrayStatus|TelephonyCapability|PhoneNumber|CarrierBundle)' | sed -E 's/(PhoneNumber: ).*/\1<set>/'
/opt/homebrew/bin/ideviceinfo -u 00008110-00184D622289801E -q com.apple.mobile.wireless_lan 2>/dev/null | head -3
