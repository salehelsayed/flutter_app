#!/bin/bash
# End of Wave 5 step 4: close the two remaining emulators and shut down the three iOS simulators.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
for s in emulator-5554 emulator-5556; do $ADB -s $s emu kill >/dev/null 2>&1 && echo "closed $s"; done
for u in 6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76 8E31AD68-4DBF-4336-AEBF-18148DC9FA07 DBE8C32E-9F19-4593-860A-B41113791D79; do xcrun simctl shutdown $u 2>/dev/null && echo "shut down simulator $u"; done
sleep 8; echo "-- adb"; $ADB devices | tail -n +2; echo "-- booted simulators: $(xcrun simctl list devices booted | grep -c Booted)"
