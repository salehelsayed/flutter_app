#!/bin/bash
# Overwrite the config.ini of a disposable Oval_/Fx_ AVD with <source>'s config (name fields replaced, audio input off).
#   host-run bash docker-ws/avd_clone_config.sh <source> <target>
S="${1:?src}"; T="${2:?target}"; [[ "$T" =~ ^(Oval_|Fx_)[A-Za-z0-9_]+$ ]] || { echo "refused"; exit 2; }
sd=$(sed -n 's/^path=//p' "$HOME/.android/avd/$S.ini"); td=$(sed -n 's/^path=//p' "$HOME/.android/avd/$T.ini")
[ -f "$sd/config.ini" ] && [ -d "$td" ] || { echo "missing"; exit 2; }
sed -e "s/^AvdId=.*/AvdId=$T/" -e "s/^avd.ini.displayname=.*/avd.ini.displayname=$T/" -e 's/^hw.audioInput=.*/hw.audioInput=no/' \
  -e 's/^showDeviceFrame=.*/showDeviceFrame=no/' "$sd/config.ini" > "$td/config.ini"
rm -f "$td"/*.lock 2>/dev/null; rm -rf "$td"/userdata-qemu.img* "$td"/cache.img* "$td"/snapshots 2>/dev/null
grep -E '^(AvdId|hw.audioInput|hw.gpu.enabled|image.sysdir.1)=' "$td/config.ini"
