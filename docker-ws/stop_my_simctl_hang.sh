#!/bin/bash
# Stop MY hung simctl chains by exact PID (children first). Each PID must be one of: my codexui_* script, a
# "simctl list devices available", the "xcodebuild -runFirstLaunch" it spawned, or the grep/head/sed in that pipe.
#   host-run bash docker-ws/stop_my_simctl_hang.sh <pid>...   (give them deepest child first)
for p in "$@"; do
  a=$(ps -o args= -p "$p" 2>/dev/null)
  case "$a" in
    *"xcodebuild -runFirstLaunch"*|*"simctl list devices available"*|*codexui_wt_inspect.sh*|*codexui_notif_red_test.sh*|"grep -E iPhone"*|"grep -E ^ +iPhone"*|"head -12"*|"head -1"*|"sed -E s/.*"*) kill "$p" && echo "TERM $p: ${a:0:70}";;
    "") echo "gone $p";;
    *) echo "refused $p: ${a:0:70}";;
  esac
done
