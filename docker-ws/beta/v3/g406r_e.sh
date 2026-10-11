#!/bin/bash
# g406r_e.sh dump <name> | tap <name> <regex> | back | shot <name> | text <string> | key <code>
. "$(dirname "$0")/emu.sh"
case "$1" in
  dump) e_dump "$2" ;;
  tap) e_tap "$2" "$3" && echo "tapped $3" ;;
  back) eadb shell input keyevent KEYCODE_BACK ;;
  shot) e_shot "$2" ;;
  text) eadb shell input text "$2" ;;
  key) eadb shell input keyevent "$2" ;;
esac
