#!/bin/bash
# Close the unused third emulator (Pixel_8, emulator-5558) and shut down the idle iPhone 15 simulator.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
$ADB -s emulator-5558 emu kill && echo "closed emulator-5558"
xcrun simctl shutdown FB7E3D88-B92D-4028-9CA7-A9CD9D34615F && echo "shut down iPhone 15 simulator"
sleep 5; $ADB devices | tail -n +2; xcrun simctl list devices booted | grep -c Booted
