#!/bin/bash
# g406r_p.sh dump <name> | tap <name> <regex> | back | shot <name> | text <string>   (Pixel 6)
export OUT=/workspace/artifacts/beta-20261011
. "$(dirname "$0")/lib.sh"
case "$1" in
  dump) p_dump "$2" ;;
  tap) p_tap_node "$2" "$3" && echo "tapped $3" ;;
  back) padb shell input keyevent KEYCODE_BACK ;;
  shot) p_shot "$2" ;;
  text) padb shell input text "$2" ;;
esac
