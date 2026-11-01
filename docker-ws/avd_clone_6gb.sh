#!/bin/bash
# Clone <source> AVD (APFS cp -c) to new AVD <target> with hw.ramSize=<mb>, audio input off, source's target copied.
#   host-run bash docker-ws/avd_clone_6gb.sh Pixel_6a Pixel_6GB 6144
S="${1:?src}"; T="${2:?target}"; RAM="${3:?mb}"
[[ "$T" =~ ^[A-Za-z0-9_]+$ ]] || { echo refused; exit 2; }
sd=$(sed -n 's/^path=//p' "$HOME/.android/avd/$S.ini"); [ -d "$sd" ] || { echo missing; exit 2; }
ps -axo command= | grep -v grep | grep -q -- "-avd $S\( \|$\)" && { echo "source running"; exit 3; }
[ -e "$HOME/.android/avd/$T.ini" ] && { echo "target exists"; exit 4; }
td="$(dirname "$sd")/$T.avd"
cp -cR "$sd" "$td" || { echo "clone failed"; exit 4; }
rm -rf "$td"/*.lock "$td"/snapshots 2>/dev/null
c="$td/config.ini"
sed -i '' -e "s/^AvdId=.*/AvdId=$T/" -e "s/^avd.ini.displayname=.*/avd.ini.displayname=$T/" -e 's/^hw.audioInput=.*/hw.audioInput=no/' -e "s/^hw.ramSize=.*/hw.ramSize=$RAM/" "$c"
grep -q '^hw.ramSize=' "$c" || echo "hw.ramSize=$RAM" >> "$c"
tgt=$(sed -n 's/^target=//p' "$HOME/.android/avd/$S.ini")
printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s.avd\ntarget=%s\n' "$td" "$T" "$tgt" > "$HOME/.android/avd/$T.ini"
grep -E '^(AvdId|hw.audioInput|hw.ramSize|abi.type|hw.cpu.arch|image.sysdir.1|hw.lcd)' "$c"
cat "$HOME/.android/avd/$T.ini"
echo "emulators running:"; ps -axo command= | grep "[q]emu-system" | grep -o -- '-avd [A-Za-z0-9_]*'
