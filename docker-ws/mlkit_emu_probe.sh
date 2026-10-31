#!/bin/bash
# Read-only: emulator version, virtual-scene poster help, poster resource file, camera config of an AVD.
#   host-run bash docker-ws/mlkit_emu_probe.sh <avd>
SDK="$HOME/Library/Android/sdk"
"$SDK/emulator/emulator" -version 2>&1 | head -1
"$SDK/emulator/emulator" -help-virtualscene-poster 2>&1 | head -12
echo "== posters file"; cat "$SDK/emulator/resources/Toren1BD.posters" 2>&1 | head -20
echo "== avd camera"; grep -i -E "camera|abi|image.sysdir|hw.audio" "$HOME/.android/avd/$1.avd/config.ini"
