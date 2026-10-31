#!/bin/bash
# setA-privintro DC-013: run only kx0010 (+ its e2e build row) through the disposable-target launcher, one emulator, Hetzner test relay file.
#   host-run bash docker-ws/setA_dc013.sh <emulator-serial>
cd /Volumes/CrucialX9/flutter_app || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:$HOME/Library/Android/sdk/platform-tools:$HOME/.maestro/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home ANDROID_HOME="$HOME/Library/Android/sdk"
export SIMS_ANDROID_EMULATOR_DEVICE_ID="${1:?serial}" SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID= SIMS_ANDROID_EMULATOR_THIRD_DEVICE_ID= SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID=
export SIMS_IOS_SIMULATOR_A_DEVICE_ID= SIMS_IOS_SIMULATOR_B_DEVICE_ID= SIMS_IOS_SIMULATOR_C_DEVICE_ID= SIMS_IOS_SIMULATOR_D_DEVICE_ID= SIMS_IOS_SIMULATOR_ID=
exec python3 docker-ws/run_sims_safe.py major --output build/kayan-safe/setA-dc013 --exclude-file build/kayan-safe/setA-dc013-exclude.txt
