#!/bin/bash
# Private Appium server on port 4735 for the iPhone automation probe (separate from 4725). start|stop <pid>|status
L=/Volumes/CrucialX9/flutter_app/build/kayan-safe/ios-automation-probe/appium4735.log
case "${1:-status}" in
  start)
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$HOME/tools/appium/node_modules/.bin/appium" --port 4735 \
      --address 127.0.0.1 --log-timestamp --log-level info > "$L" 2>&1 < /dev/null &
    for i in $(seq 1 30); do curl -s http://127.0.0.1:4735/status | grep -q '"ready":true' && break; sleep 1; done
    curl -s http://127.0.0.1:4735/status | head -c 200; echo
    ps -axo pid=,args= | grep 'appium --port 4735' | grep -v grep | cut -c1-120 ;;
  stop)
    P="$2"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
    case "$(ps -o args= -p "$P")" in *appium*--port\ 4735*) kill "$P" && echo "TERM $P";; *) echo "refused: not appium 4735";; esac ;;
  status) ps -axo pid=,args= | grep 'appium --port 4735' | grep -v grep | cut -c1-120; tail -5 "$L" ;;
esac
