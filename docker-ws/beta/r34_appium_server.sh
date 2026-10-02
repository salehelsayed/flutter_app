#!/bin/bash
# Private Appium server for the R2 iPhone validation (port 4725, 127.0.0.1; separate from the shared appium-mcp, which
# deletes every session when any client disconnects). Usage: r34_appium_server.sh start|stop|status
L=/Volumes/CrucialX9/flutter_app/docker-ws/beta/r34_appium_server.log
case "${1:-status}" in
  start)
    pgrep -f "appium --port 4725" >/dev/null && { echo "already running"; exit 0; }
    nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$HOME/tools/appium/node_modules/.bin/appium" --port 4725 \
      --address 127.0.0.1 --log-timestamp --log-level info > "$L" 2>&1 < /dev/null &
    for i in $(seq 1 30); do curl -s http://127.0.0.1:4725/status | grep -q '"ready":true' && break; sleep 1; done
    curl -s http://127.0.0.1:4725/status | head -c 300; echo ;;
  stop) pkill -f "appium --port 4725"; echo stopped ;;
  status) pgrep -fl "appium --port 4725"; curl -s http://127.0.0.1:4725/status | head -c 200; echo; tail -5 "$L" ;;
esac
