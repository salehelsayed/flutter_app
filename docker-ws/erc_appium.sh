#!/bin/bash
# Private Appium server on port 4725 for the safe Transfer rows. start|stop <pid>|status
L=/Volumes/CrucialX9/flutter_app/.codex-test-logs/erase-claims-20261023T2103Z/appium4725.log
case "${1:-status}" in
  start)
    mkdir -p "$(dirname "$L")"
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$HOME/tools/appium/node_modules/.bin/appium" --port 4725 \
      --log-timestamp --log-level info > "$L" 2>&1 < /dev/null &
    for i in $(seq 1 30); do curl -s http://127.0.0.1:4725/status | grep -q '"ready":true' && break; sleep 1; done
    curl -s http://127.0.0.1:4725/status | head -c 120; echo
    ps -axo pid=,args= | grep 'appium --port 4725' | grep -v grep | cut -c1-120 ;;
  stop)
    P="$2"; [[ "$P" =~ ^[0-9]+$ ]] || { echo refused; exit 2; }
    case "$(ps -o args= -p "$P")" in *appium*--port\ 4725*) kill "$P" && echo "TERM $P";; *) echo "refused: not appium 4725";; esac ;;
  status) ps -axo pid=,args= | grep 'appium --port 4725' | grep -v grep | cut -c1-120; tail -3 "$L" ;;
esac
