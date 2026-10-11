# Helpers for the AliceOld/AliceH emulator (emulator-5560). Source it: . docker-ws/beta/v3/emu.sh
export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
EOUT=/workspace/artifacts/beta-20261011/ui; mkdir -p "$EOUT"
eadb() { timeout 120 /claude-host-bin/adb -s emulator-5560 "$@"; }
e_dump() {  # e_dump <name>: UI tree; prints text/content-desc of every node
  eadb shell rm -f /sdcard/e.xml; eadb shell uiautomator dump /sdcard/e.xml >/dev/null 2>&1
  eadb shell cat /sdcard/e.xml > "$EOUT/e_$1.xml"
  grep -oE '(text|content-desc)="[^"]+"' "$EOUT/e_$1.xml" | sed -E 's/^(text|content-desc)=//' | tr '\n' ' '
}
e_tap() {  # e_tap <name> <regex on text, content-desc or resource-id>
  local b
  b=$(grep -oE '<node [^>]*>' "$EOUT/e_$1.xml" | grep -E "(text|content-desc|resource-id)=\"$2\"" | head -1 | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '[0-9]+')
  [ -z "$b" ] && { echo "no node $2"; return 1; }
  set -- $b; eadb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
}
e_shot() { eadb shell screencap -p /sdcard/e.png; eadb pull /sdcard/e.png "$EOUT/../shots/$1.png" >/dev/null 2>&1; echo "$EOUT/../shots/$1.png"; }
