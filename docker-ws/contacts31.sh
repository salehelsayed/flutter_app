#!/bin/bash
# Lever for the 2026-10-31 P0 CONTACTS group (iPhones). Page-source text only, never screenshots.
#   contacts31.sh ssrc <11|13> <ERE>       iOS Settings: print only element lines whose label matches ERE (keeps other Settings content out of logs)
#   contacts31.sh settings <11|13>         open iOS Settings at Mknoon's own page (fresh Settings launch + search "mknoon")
#   contacts31.sh toggle <11|13> <label>   read then tap the Switch with that label in Settings; prints value before/after
#   contacts31.sh back <11|13>             return to Mknoon (activate) and print its foreground state
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/beta" || exit 2
AP() { timeout 120 python3 ap.py "$@"; }
case "$1" in
  ssrc) AP "$2" src '.' | awk -F'|' -v re="$3" '$2 ~ re {print $1"|"$2"|"$4"|"$5}' ;;
  settings)
    AP "$2" app terminate com.apple.Preferences >/dev/null; sleep 1
    AP "$2" app activate com.apple.Preferences >/dev/null; sleep 2
    AP "$2" tap "type == 'XCUIElementTypeSearchField'" >/dev/null || exit 3; sleep 1
    AP "$2" key "mknoon" >/dev/null; sleep 2
    AP "$2" tap "type == 'XCUIElementTypeCell' AND label CONTAINS[c] 'mknoon'" >/dev/null || AP "$2" tap "label ==[c] 'mknoon' AND type != 'XCUIElementTypeSearchField'" >/dev/null || exit 4
    sleep 2; AP "$2" src '.' | awk -F'|' '$1 ~ /Switch|Cell|Button|NavigationBar/ && $2 ~ /mknoon|Camera|Notifications|Allow|Alerts|Lock|Banners|Sounds|Badges|Back/ {print $1"|"$2"|"$4}' ;;
  toggle)
    P="type == 'XCUIElementTypeSwitch' AND (label == '$3' OR name == '$3')"
    echo "before=$(AP "$2" attr "$P" value)"
    R=$(AP "$2" find "$P" | python3 -c "import sys,ast; d=ast.literal_eval(sys.stdin.read().split(' | ')[-1]); print(d['x'],d['y'],d['width'],d['height'])")
    read -r X Y W H <<<"$R"; [ -n "$H" ] || exit 3
    AP "$2" tapxy $((X+W-30)) $((Y+H/2)) >/dev/null; sleep 2   # the row centre is the label; the knob is at the right edge
    echo "after=$(AP "$2" attr "$P" value 2>&1 | tail -1) $(date -u +%T)" ;;
  back) AP "$2" app activate com.mknoon.app >/dev/null; sleep 3; echo "state=$(AP "$2" app state) $(date -u +%T)" ;;
  *) sed -n 2,6p "$0"; exit 2 ;;
esac
