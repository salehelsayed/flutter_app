#!/bin/bash
# Fresh-account lever for the 2026-10-31 P0 campaign: drives the disposable emulator-5554 (p0emu) by UI dump text only.
#   fresh31_emu.sh del <contact-name>   all chats -> swipe the row -> Delete -> confirm -> back to Orbit
#   fresh31_emu.sh scan                 Settings -> Scan (camera = QR poster) -> print the result dialog
#   fresh31_emu.sh ui                   print focus + visible texts
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
cd "$(dirname "$0")/.." || exit 2
S=emulator-5554; U="bash docker-ws/setA_ui.sh"
bounds() { timeout 20 adb -s $S shell 'uiautomator dump /sdcard/u.xml >/dev/null; cat /sdcard/u.xml' | tr '>' '\n' | grep -F -- "$1" | tail -1 | grep -o 'bounds="[^"]*"' | tr -c '0-9' ' '; }
tapb() { read -r a b c d <<<"$(bounds "$1")"; [ -n "$d" ] || { echo "NOT FOUND: $1"; return 3; }; adb -s $S shell input tap $(((a+c)/2)) $(((b+d)/2)); }
case "$1" in
  ui) $U texts $S ;;
  del)
    $U tap $S "Show all chats" >/dev/null; sleep 3
    read -r a b c d <<<"$(bounds "content-desc=\"$2")"; [ -n "$d" ] || { echo "no row $2"; exit 3; }
    y=$(((b+d)/2)); adb -s $S shell input swipe 900 $y 200 $y 400; sleep 2
    tapb 'content-desc="Delete"' || exit 3; sleep 2
    tapb 'content-desc="Delete"' || exit 3; sleep 3
    $U tap $S "Show inner circle" >/dev/null; sleep 2; $U texts $S | head -4 ;;
  scan)
    $U tap $S "Open settings" >/dev/null; sleep 3
    tapb 'content-desc="Scan"' || exit 3; sleep 8
    $U texts $S | head -6; echo "scan_done $(date -u +%T)"
    $U tap $S 'content-desc="OK"' >/dev/null ;;
  *) sed -n 2,5p "$0"; exit 2 ;;
esac
