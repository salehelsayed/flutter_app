#!/bin/bash
# Pixel cold launch N: HOME, am kill, launch, open Settings > Media & storage translator row, poll it.
cd /workspace; export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037; S=21071FDF600CSC
A(){ timeout 30 adb -s $S "$@"; }
A shell input keyevent 3; sleep 2; A shell am kill com.mknoon.app; sleep 2
echo "pid after kill: '$(A shell pidof com.mknoon.app)'"
echo "launch $(date -u +%T)"; A shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in 1 2 3 4 5 6; do sleep 1; python3 docker-ws/px_ui.py has "Open settings" >/dev/null && break; done
python3 docker-ws/px_ui.py tap "Open settings"; sleep 1; python3 docker-ws/px_ui.py tap "Media & storage"; sleep 1
A shell input swipe 540 1900 540 500 300; A shell input swipe 540 1900 540 500 300
for i in $(seq 1 ${1:-6}); do echo "$(date -u +%T) $(python3 docker-ws/px_ui.py dump | grep -A2 'Private translator' | cut -f2 | tr '\n' ' ')"; sleep 2; done
