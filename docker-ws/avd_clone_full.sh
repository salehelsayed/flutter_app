#!/bin/bash
# Replace the dir of a disposable Oval_/Fx_ AVD with an APFS clone (cp -c, no extra space) of <source>'s AVD dir. Source must not be running.
#   host-run bash docker-ws/avd_clone_full.sh <source> <target>
S="${1:?src}"; T="${2:?target}"; [[ "$T" =~ ^(Oval_|Fx_)[A-Za-z0-9_]+$ ]] || { echo "refused"; exit 2; }
sd=$(sed -n 's/^path=//p' "$HOME/.android/avd/$S.ini"); td=$(sed -n 's/^path=//p' "$HOME/.android/avd/$T.ini")
[ -d "$sd" ] && [ -n "$td" ] || { echo "missing"; exit 2; }
ps -axo command= | grep -v grep | grep -q -- "-avd $S\( \|$\)" && { echo "source running"; exit 3; }
rm -rf "$td" && cp -cR "$sd" "$td" || { echo "clone failed"; exit 4; }
rm -rf "$td"/*.lock "$td"/snapshots 2>/dev/null
sed -i '' -e "s/^AvdId=.*/AvdId=$T/" -e "s/^avd.ini.displayname=.*/avd.ini.displayname=$T/" -e 's/^hw.audioInput=.*/hw.audioInput=no/' "$td/config.ini"
grep -E '^(AvdId|hw.audioInput)=' "$td/config.ini"
# avdmanager writes target=android-0 for this image, which makes the emulator start without hvf. Copy the source's target.
tgt=$(sed -n 's/^target=//p' "$HOME/.android/avd/$S.ini")
printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s.avd\ntarget=%s\n' "$td" "$T" "$tgt" > "$HOME/.android/avd/$T.ini"
cat "$HOME/.android/avd/$T.ini"
