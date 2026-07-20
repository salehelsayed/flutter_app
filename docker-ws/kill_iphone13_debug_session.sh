#!/bin/bash
# Tear down the 2026-07-20 iPhone-13 debug diagnosis session: the flutter run
# tool, its devicectl console attach, and the idevicesyslog capture. Patterns
# are pinned to the iPhone-13 UDID so concurrent sessions' flutter/devicectl
# processes are untouched.
pkill -f 'run --debug -d 00008110-00184D622289801E' && echo "killed flutter run (iphone13 debug)" || echo "flutter run not running"
pkill -f 'devicectl device process launch --device 00008110-00184D622289801E' && echo "killed devicectl console attach" || echo "no devicectl console attach"
pkill -f 'idevicesyslog -u 00008110-00184D622289801E' && echo "killed idevicesyslog capture" || echo "no idevicesyslog capture"
exit 0
