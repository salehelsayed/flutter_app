#!/bin/bash
# Boot the four Wave 5 iOS simulators (A to D) and wait until each is fully booted.
for u in 6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76 8E31AD68-4DBF-4336-AEBF-18148DC9FA07 DBE8C32E-9F19-4593-860A-B41113791D79 FB7E3D88-B92D-4028-9CA7-A9CD9D34615F; do
  xcrun simctl boot "$u" 2>&1 | grep -v "current state: Booted"
done
for u in 6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76 8E31AD68-4DBF-4336-AEBF-18148DC9FA07 DBE8C32E-9F19-4593-860A-B41113791D79 FB7E3D88-B92D-4028-9CA7-A9CD9D34615F; do
  timeout 100 xcrun simctl bootstatus "$u" -b >/dev/null 2>&1; echo "$u rc=$?"
done
xcrun simctl list devices booted | grep -c Booted
